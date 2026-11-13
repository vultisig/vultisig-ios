//
//  HyperliquidCoSignVerifier.swift
//  VultisigApp
//
//  The joiner's check of a Hyperliquid keysign payload, before any relay
//  traffic. The keysign digest of an L1 action is an opaque
//  `Agent{source, connectionId}` hash, so without this a paired device signs
//  blind. Steps:
//    1. Detect Hyperliquid by the typed data's shape, never by the preimage
//       field: a payload that looks like Hyperliquid but carries no preimage
//       is refused, or a compromised initiator would simply drop the field.
//    2. L1: decode the msgpack strictly (re-encoding must give the same
//       bytes), rebuild `connectionId` and the Agent digest, and require it
//       to equal the digest keysign would sign.
//    3. Allowlist the action: known types, exact keys, no vault address,
//       the pinned builder at no more than the approved fee.
//    4. Time: an L1 action must expire within 180 s of its nonce, and the
//       nonce must be within 10 minutes of this device's clock.
//    5. User-signed: pin the withdraw destination to this vault's own main
//       address, `time` to the nonce, the network, the builder and its cap.
//    6. Return the lines the confirm screen shows.
//  The initiator runs the same function on its own payload.
//

import Foundation

enum HyperliquidCoSignRefusal: Error, Equatable, LocalizedError {
    case missingPreimage
    case malformed
    case kindMismatch
    case nonCanonicalAction
    case digestMismatch
    case unknownAction(String)
    case unexpectedKeys(String)
    case vaultAddressSet
    case builderMismatch
    case builderFeeTooHigh
    case missingExpiry
    case expiryTooLong
    case nonceOutOfRange
    case networkMismatch
    case withdrawDestination
    case withdrawTimeMismatch
    case maxFeeTooHigh
    case emptyAgentName

    var errorDescription: String? {
        self == .missingPreimage ? "perpsCoSignCannotVerify".localized : "perpsCoSignRefused".localized
    }
}

struct HyperliquidCoSignContext {
    /// This device's own main EVM address for the vault, from its own keys.
    var mainAddress: String?
    /// This device's own trading-account address for the vault.
    var tradingAddress: String?
    var builderAddress: String = PerpsConfig.builderAddress
    var maxBuilderFeeTenthsBp: Int = PerpsConfig.builderFeeTenthsBp
    var maxBuilderFeeRate: Decimal = Decimal(string: "0.1") ?? 0
    var nowMs: UInt64 = HLVenueClock.shared.nowMs
    var coinName: (Int) -> String? = { PerpsMarketCache.shared.name(for: $0) }
}

struct PerpsCoSignSummary: Equatable, Sendable {
    let lines: [String]
    /// "Trading account · 0x1185…" when the payload asks for the trading path.
    let signingAs: String?
}

enum HyperliquidCoSignVerifier {
    static let maxExpiryMs: UInt64 = 180_000
    static let maxClockSkewMs: UInt64 = 600_000

    enum Shape: Equatable {
        case l1
        case userSigned(primaryType: String)
    }

    /// Nil when the payload is not Hyperliquid at all (any other dApp
    /// message signs as before). Throws a refusal otherwise.
    static func verify(_ payload: CustomMessagePayload, context: HyperliquidCoSignContext) throws -> PerpsCoSignSummary? {
        guard payload.method == "eth_signTypedData_v4", let typed = parse(payload.message), let shape = shape(of: typed) else { return nil }
        guard let preimage = payload.hyperliquid else { throw HyperliquidCoSignRefusal.missingPreimage }
        try checkNonceTime(preimage.nonce, context: context)
        let lines: [String]
        switch shape {
        case .l1:
            lines = try verifyL1(preimage, keysignDigest: payload.keysignMessages.first, context: context)
        case .userSigned(let primaryType):
            lines = try verifyUserSigned(preimage, primaryType: primaryType, typed: typed, context: context)
        }
        // Only when the payload names the trading path. A joiner learns it once
        // `derive_path` travels in the proto; until then the row is left out.
        let signingAs = payload.derivePath == PerpsSignerAccount.trading.derivationPath
            ? context.tradingAddress.map { "perpsTradingAccountShort".localized + " · " + PerpsFormat.shortAddress($0) }
            : nil
        return PerpsCoSignSummary(lines: lines, signingAs: signingAs)
    }

    static func shape(of typed: [String: Any]) -> Shape? {
        guard let domain = typed["domain"] as? [String: Any], let name = domain["name"] as? String,
              let primaryType = typed["primaryType"] as? String else { return nil }
        if name == "Exchange" && primaryType == "Agent" { return .l1 }
        if name == "HyperliquidSignTransaction" && primaryType.hasPrefix("HyperliquidTransaction:") {
            return .userSigned(primaryType: primaryType)
        }
        return nil
    }

    private static func parse(_ message: String) -> [String: Any]? {
        guard let data = message.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func checkNonceTime(_ nonce: UInt64, context: HyperliquidCoSignContext) throws {
        let skew = nonce > context.nowMs ? nonce - context.nowMs : context.nowMs - nonce
        guard skew <= maxClockSkewMs else { throw HyperliquidCoSignRefusal.nonceOutOfRange }
    }

    // MARK: - L1

    private static func verifyL1(_ preimage: HyperliquidActionPreimage, keysignDigest: String?,
                                 context: HyperliquidCoSignContext) throws -> [String] {
        guard preimage.vaultAddress == nil else { throw HyperliquidCoSignRefusal.vaultAddressSet }
        guard let expiresAfter = preimage.expiresAfter else { throw HyperliquidCoSignRefusal.missingExpiry }
        guard expiresAfter > preimage.nonce, expiresAfter - preimage.nonce <= maxExpiryMs else { throw HyperliquidCoSignRefusal.expiryTooLong }
        let action: HLValue
        do {
            action = try HLMsgPackDecoder.decodeCanonical(preimage.actionMsgpack)
        } catch {
            throw HyperliquidCoSignRefusal.nonCanonicalAction
        }
        guard case .string(let type)? = action["type"], type == preimage.kind else { throw HyperliquidCoSignRefusal.kindMismatch }
        let rebuilt = try HLActionHasher.l1TypedData(action: action, nonce: preimage.nonce, isMainnet: preimage.isMainnet,
                                                     vaultAddress: nil, expiresAfter: expiresAfter)
        guard let keysignDigest, rebuilt.digest.hexString.lowercased() == keysignDigest.lowercased().stripHexPrefix() else {
            throw HyperliquidCoSignRefusal.digestMismatch
        }
        return try HLCoSignActionReader(context: context).lines(for: action, type: type)
    }

    // MARK: - User-signed

    private static func verifyUserSigned(_ preimage: HyperliquidActionPreimage, primaryType: String, typed: [String: Any],
                                         context: HyperliquidCoSignContext) throws -> [String] {
        guard preimage.actionMsgpack.isEmpty, let message = typed["message"] as? [String: Any] else { throw HyperliquidCoSignRefusal.malformed }
        guard message["hyperliquidChain"] as? String == (preimage.isMainnet ? "Mainnet" : "Testnet") else {
            throw HyperliquidCoSignRefusal.networkMismatch
        }
        switch primaryType {
        case "HyperliquidTransaction:Withdraw":
            guard preimage.kind == "withdraw3" else { throw HyperliquidCoSignRefusal.kindMismatch }
            guard let destination = message["destination"] as? String, let own = context.mainAddress,
                  destination.lowercased() == own.lowercased() else { throw HyperliquidCoSignRefusal.withdrawDestination }
            guard uint64(message["time"]) == preimage.nonce else { throw HyperliquidCoSignRefusal.withdrawTimeMismatch }
            guard let amount = message["amount"] as? String else { throw HyperliquidCoSignRefusal.malformed }
            return [String(format: "perpsCoSignWithdraw".localized, amount)]
        case "HyperliquidTransaction:ApproveBuilderFee":
            guard preimage.kind == "approveBuilderFee", uint64(message["nonce"]) == preimage.nonce else { throw HyperliquidCoSignRefusal.kindMismatch }
            guard (message["builder"] as? String)?.lowercased() == context.builderAddress.lowercased() else {
                throw HyperliquidCoSignRefusal.builderMismatch
            }
            guard let rate = message["maxFeeRate"] as? String, let percent = percentValue(rate), percent <= context.maxBuilderFeeRate else {
                throw HyperliquidCoSignRefusal.maxFeeTooHigh
            }
            return [String(format: "perpsCoSignApproveBuilder".localized, rate)]
        case "HyperliquidTransaction:ApproveAgent":
            guard preimage.kind == "approveAgent", uint64(message["nonce"]) == preimage.nonce else { throw HyperliquidCoSignRefusal.kindMismatch }
            guard let name = message["agentName"] as? String, !name.isEmpty else { throw HyperliquidCoSignRefusal.emptyAgentName }
            guard let agent = message["agentAddress"] as? String else { throw HyperliquidCoSignRefusal.malformed }
            return [String(format: "perpsCoSignApproveAgent".localized, PerpsFormat.shortAddress(agent), name)]
        default:
            throw HyperliquidCoSignRefusal.unknownAction(primaryType)
        }
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let text = value as? String { return UInt64(text) }
        return nil
    }

    /// "0.1%" -> 0.1
    private static func percentValue(_ text: String) -> Decimal? {
        guard text.hasSuffix("%") else { return nil }
        return Decimal(string: String(text.dropLast()), locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Strict reader of the L1 actions perps signs: known types, exact keys.
struct HLCoSignActionReader {
    let context: HyperliquidCoSignContext

    func lines(for action: HLValue, type: String) throws -> [String] {
        switch type {
        case "order":
            try keys(action, required: ["type", "orders", "grouping"], optional: ["builder"])
            guard case .string(let grouping)? = action["grouping"], HLGrouping(rawValue: grouping) != nil,
                  case .array(let orders)? = action["orders"], !orders.isEmpty else { throw HyperliquidCoSignRefusal.malformed }
            var lines = try orders.map(orderLine)
            if let builder = action["builder"] { lines.append(try builderLine(builder)) }
            return lines
        case "cancel":
            try keys(action, required: ["type", "cancels"])
            guard case .array(let cancels)? = action["cancels"], !cancels.isEmpty else { throw HyperliquidCoSignRefusal.malformed }
            return try cancels.map { cancel in
                try keys(cancel, required: ["a", "o"])
                return String(format: "perpsCoSignCancel".localized, try int(cancel["o"]).description, coin(try int(cancel["a"])))
            }
        case "batchModify":
            try keys(action, required: ["type", "modifies"])
            guard case .array(let modifies)? = action["modifies"], !modifies.isEmpty else { throw HyperliquidCoSignRefusal.malformed }
            return try modifies.map { modify in
                try keys(modify, required: ["oid", "order"])
                return try modifyLine(oid: modify["oid"], order: modify["order"])
            }
        case "updateLeverage":
            try keys(action, required: ["type", "asset", "isCross", "leverage"])
            guard case .bool(let isCross)? = action["isCross"] else { throw HyperliquidCoSignRefusal.malformed }
            return [String(format: "perpsCoSignLeverage".localized, coin(try int(action["asset"])), try int(action["leverage"]).description,
                           isCross ? "perpsCross".localized : "perpsIsolated".localized)]
        case "updateIsolatedMargin":
            try keys(action, required: ["type", "asset", "isBuy", "ntli"])
            let ntli = try int(action["ntli"])
            let usd = HLWireFormat.decimalString(Decimal(ntli.magnitude) / 1_000_000)
            return [String(format: (ntli >= 0 ? "perpsCoSignAddMargin" : "perpsCoSignRemoveMargin").localized, usd, coin(try int(action["asset"])))]
        case "noop":
            try keys(action, required: ["type"])
            return ["perpsCoSignNoop".localized]
        default:
            throw HyperliquidCoSignRefusal.unknownAction(type)
        }
    }

    private func modifyLine(oid: HLValue?, order: HLValue?) throws -> String {
        guard let order else { throw HyperliquidCoSignRefusal.malformed }
        return String(format: "perpsCoSignModify".localized, try int(oid).description, try orderLine(order))
    }

    /// "Buy 0.0002 BTC, market, worst price $67,500" / "Stop loss at $62,000".
    private func orderLine(_ order: HLValue) throws -> String {
        try keys(order, required: ["a", "b", "p", "s", "r", "t"], optional: ["c"])
        guard case .bool(let isBuy)? = order["b"], case .string(let price)? = order["p"], case .string(let size)? = order["s"],
              case .bool(let reduceOnly)? = order["r"], let type = order["t"] else { throw HyperliquidCoSignRefusal.malformed }
        let coin = coin(try int(order["a"]))
        if let trigger = type["trigger"] {
            try keys(type, required: ["trigger"])
            try keys(trigger, required: ["isMarket", "triggerPx", "tpsl"])
            guard case .string(let triggerPx)? = trigger["triggerPx"], case .string(let tpsl)? = trigger["tpsl"],
                  let kind = HLOrderType.Kind(rawValue: tpsl) else { throw HyperliquidCoSignRefusal.malformed }
            let key = kind == .stopLoss ? "perpsCoSignStopAt" : "perpsCoSignTakeAt"
            return String(format: key.localized, PerpsFormat.plainPrice(Self.decimal(triggerPx), grouped: true))
        }
        try keys(type, required: ["limit"])
        guard let limit = type["limit"] else { throw HyperliquidCoSignRefusal.malformed }
        try keys(limit, required: ["tif"])
        guard case .string(let tif)? = limit["tif"], let timeInForce = HLTimeInForce(rawValue: tif) else { throw HyperliquidCoSignRefusal.malformed }
        let side = String(format: (isBuy ? "perpsCoSignBuy" : "perpsCoSignSell").localized, size, coin)
        let priceText = PerpsFormat.plainPrice(Self.decimal(price), grouped: true)
        var parts = [side, String(format: (timeInForce == .ioc ? "perpsCoSignMarket" : "perpsCoSignLimit").localized, priceText)]
        if reduceOnly { parts.append("perpsCoSignReduceOnly".localized) }
        return parts.joined(separator: ", ")
    }

    private func builderLine(_ builder: HLValue) throws -> String {
        try keys(builder, required: ["b", "f"])
        guard case .string(let address)? = builder["b"], address.lowercased() == context.builderAddress.lowercased() else {
            throw HyperliquidCoSignRefusal.builderMismatch
        }
        let tenths = try int(builder["f"])
        guard tenths >= 0, tenths <= Int64(context.maxBuilderFeeTenthsBp) else { throw HyperliquidCoSignRefusal.builderFeeTooHigh }
        // Tenths of a basis point: 100 -> 0.1%.
        return String(format: "perpsCoSignBuilderFee".localized, HLWireFormat.decimalString(Decimal(tenths) / 1_000) + "%")
    }

    private func coin(_ asset: Int64) -> String {
        context.coinName(Int(asset)) ?? String(format: "perpsCoSignAsset".localized, asset.description)
    }

    private func int(_ value: HLValue?) throws -> Int64 {
        switch value {
        case .int(let number)?: return number
        case .uint(let number)? where number <= UInt64(Int64.max): return Int64(number)
        default: throw HyperliquidCoSignRefusal.malformed
        }
    }

    private func keys(_ value: HLValue, required: Set<String>, optional: Set<String> = []) throws {
        guard case .map(let entries) = value else { throw HyperliquidCoSignRefusal.malformed }
        let present = entries.map(\.key)
        guard Set(present).count == present.count else { throw HyperliquidCoSignRefusal.unexpectedKeys("duplicate") }
        let extra = Set(present).subtracting(required.union(optional))
        guard extra.isEmpty else { throw HyperliquidCoSignRefusal.unexpectedKeys(extra.sorted().joined(separator: ",")) }
        guard required.isSubset(of: Set(present)) else { throw HyperliquidCoSignRefusal.malformed }
    }

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}

/// Coin names by asset index and the latest mid per coin, kept from the
/// last `metaAndAssetCtxs` read. A co-signer that never opened perps shows
/// "asset #3": honest, and it does not touch the digest. Stamping re-quotes
/// a market order from `mid(coin:)`.
final class PerpsMarketCache: @unchecked Sendable {
    static let shared = PerpsMarketCache()

    private let lock = NSLock()
    private var names: [Int: String] = [:]
    private var mids: [String: Decimal] = [:]

    func record(_ markets: [PerpsMarket]) {
        lock.withLock {
            names = Dictionary(markets.map { ($0.assetIndex, $0.coin) }, uniquingKeysWith: { first, _ in first })
            mids = Dictionary(markets.map { ($0.coin, $0.midPrice ?? $0.markPrice) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func name(for asset: Int) -> String? {
        lock.withLock { names[asset] }
    }

    func mid(coin: String) -> Decimal? {
        lock.withLock { mids[coin] }
    }
}
