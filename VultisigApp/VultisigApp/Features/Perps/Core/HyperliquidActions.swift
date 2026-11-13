//
//  HyperliquidActions.swift
//  VultisigApp
//
//  Builders for the Hyperliquid actions perps models. Key order
//  follows the venue's canonical struct order (the Python SDK's
//  `order_request_to_order_wire`: a, b, p, s, r, t, c), because the venue
//  re-serialises the parsed action before checking the signature.
//

import Foundation

enum HLTimeInForce: String, Sendable {
    case gtc = "Gtc"
    case ioc = "Ioc"
    case alo = "Alo"
}

enum HLOrderType: Equatable, Sendable {
    case limit(HLTimeInForce)
    case trigger(isMarket: Bool, triggerPrice: String, kind: Kind)

    enum Kind: String, Sendable {
        case takeProfit = "tp"
        case stopLoss = "sl"
    }

    var wire: HLValue {
        switch self {
        case .limit(let tif):
            return .object([("limit", .object([("tif", .string(tif.rawValue))]))])
        case let .trigger(isMarket, triggerPrice, kind):
            return .object([("trigger", .object([
                ("isMarket", .bool(isMarket)),
                ("triggerPx", .string(triggerPrice)),
                ("tpsl", .string(kind.rawValue))
            ]))])
        }
    }
}

struct HLOrderWire: Equatable, Sendable {
    let asset: Int
    let isBuy: Bool
    let price: String
    let size: String
    let reduceOnly: Bool
    let type: HLOrderType
    var clientOrderId: String?

    var wire: HLValue {
        var entries: [(String, HLValue)] = [
            ("a", .int(Int64(asset))),
            ("b", .bool(isBuy)),
            ("p", .string(price)),
            ("s", .string(size)),
            ("r", .bool(reduceOnly)),
            ("t", type.wire)
        ]
        if let clientOrderId { entries.append(("c", .string(clientOrderId))) }
        return .object(entries)
    }
}

enum HLGrouping: String, Sendable {
    case standalone = "na"
    case normalTpsl
    case positionTpsl
}

struct HLBuilderFee: Equatable, Sendable {
    /// Builder address, lowercase 0x-hex.
    let builder: String
    /// Fee in tenths of a basis point (10 = 1bp).
    let tenthsOfBasisPoint: Int
}

enum HLActions {
    static func order(_ orders: [HLOrderWire], grouping: HLGrouping = .standalone, builder: HLBuilderFee? = nil) -> HLValue {
        var entries: [(String, HLValue)] = [
            ("type", .string("order")),
            ("orders", .array(orders.map(\.wire))),
            ("grouping", .string(grouping.rawValue))
        ]
        if let builder {
            entries.append(("builder", .object([("b", .string(builder.builder.lowercased())), ("f", .int(Int64(builder.tenthsOfBasisPoint)))])))
        }
        return .object(entries)
    }

    /// `{type:"cancel", cancels:[{a, o}]}`, the SDK's `bulk_cancel`.
    static func cancel(_ cancels: [(asset: Int, oid: Int64)]) -> HLValue {
        .object([
            ("type", .string("cancel")),
            ("cancels", .array(cancels.map { .object([("a", .int(Int64($0.asset))), ("o", .int($0.oid))]) }))
        ])
    }

    /// `ntli` is USD in 6-decimal integer units (the SDK's `float_to_usd_int`);
    /// negative removes margin. `isBuy` has no effect but is part of the hashed struct.
    static func updateIsolatedMargin(asset: Int, usd: Decimal) -> HLValue {
        .object([
            ("type", .string("updateIsolatedMargin")),
            ("asset", .int(Int64(asset))),
            ("isBuy", .bool(true)),
            ("ntli", .int(usdInt(usd)))
        ])
    }

    static func usdInt(_ usd: Decimal) -> Int64 {
        var scaled = usd * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func updateLeverage(asset: Int, isCross: Bool, leverage: Int) -> HLValue {
        .object([
            ("type", .string("updateLeverage")),
            ("asset", .int(Int64(asset))),
            ("isCross", .bool(isCross)),
            ("leverage", .int(Int64(leverage)))
        ])
    }
}

// MARK: - User-signed actions (vault key, HyperliquidSignTransaction domain)

/// A user-signed action: the JSON posted to /exchange plus the EIP-712 the
/// vault signs for it. Both are derived from the same fields so they cannot drift.
struct HLUserSignedAction: Equatable, Sendable {
    let action: HLValue
    let typedData: HLTypedData
    let nonce: UInt64

    /// The Python SDK hard-codes `0x66eee` (421614) for both networks;
    /// `hyperliquidChain` is what prevents cross-network replay. Kept as the
    /// default for SDK parity; the app passes `PerpsConfig.signatureChainId`
    /// (0xa4b1, Arbitrum One) as the integration spec recommends.
    static let defaultSignatureChainId: UInt64 = 0x66eee

    static func approveAgent(
        agentAddress: String,
        agentName: String?,
        nonce: UInt64,
        isMainnet: Bool,
        signatureChainId: UInt64 = defaultSignatureChainId
    ) throws -> HLUserSignedAction {
        let address = try HLAddress.bytes(agentAddress)
        let chain = isMainnet ? "Mainnet" : "Testnet"
        let chainIdHex = "0x" + String(signatureChainId, radix: 16)
        var entries: [(String, HLValue)] = [
            ("type", .string("approveAgent")),
            ("signatureChainId", .string(chainIdHex)),
            ("hyperliquidChain", .string(chain)),
            ("agentAddress", .string("0x" + address.hexString))
        ]
        // The SDK signs an empty name but omits the key from the posted action.
        if let agentName { entries.append(("agentName", .string(agentName))) }
        entries.append(("nonce", .uint(nonce)))
        let typed = HLTypedData(
            domain: .userSigned(signatureChainId: signatureChainId),
            primaryType: "HyperliquidTransaction:ApproveAgent",
            fields: [
                HLTypedField(name: "hyperliquidChain", value: .string(chain)),
                HLTypedField(name: "agentAddress", value: .address(address)),
                HLTypedField(name: "agentName", value: .string(agentName ?? "")),
                HLTypedField(name: "nonce", value: .uint64(nonce))
            ]
        )
        return HLUserSignedAction(action: .object(entries), typedData: typed, nonce: nonce)
    }

    /// Agent name with the on-chain expiry suffix (`valid_until <ms>`, max 180 days ahead).
    static func agentName(_ name: String, validUntilMs: UInt64?) -> String {
        guard let validUntilMs else { return name }
        return "\(name) valid_until \(validUntilMs)"
    }

    static let maxAgentLifetimeMs: UInt64 = 180 * 86_400_000

    /// `withdraw3`: USDC from the perps balance to `destination` on Arbitrum.
    /// Vault (master) only. The signed field is `time`, which must equal the outer nonce.
    static func withdraw3(
        destination: String,
        amount: Decimal,
        nonce: UInt64,
        isMainnet: Bool,
        signatureChainId: UInt64 = defaultSignatureChainId
    ) throws -> HLUserSignedAction {
        let address = "0x" + (try HLAddress.bytes(destination)).hexString
        let chain = isMainnet ? "Mainnet" : "Testnet"
        let amountText = try HLWireFormat.wire(amount)
        let action = HLValue.object([
            ("type", .string("withdraw3")),
            ("signatureChainId", .string("0x" + String(signatureChainId, radix: 16))),
            ("hyperliquidChain", .string(chain)),
            ("destination", .string(address)),
            ("amount", .string(amountText)),
            ("time", .uint(nonce))
        ])
        let typed = HLTypedData(
            domain: .userSigned(signatureChainId: signatureChainId),
            primaryType: "HyperliquidTransaction:Withdraw",
            fields: [
                HLTypedField(name: "hyperliquidChain", value: .string(chain)),
                HLTypedField(name: "destination", value: .string(address)),
                HLTypedField(name: "amount", value: .string(amountText)),
                HLTypedField(name: "time", value: .uint64(nonce))
            ]
        )
        return HLUserSignedAction(action: action, typedData: typed, nonce: nonce)
    }

    static func approveBuilderFee(
        builder: String,
        maxFeeRate: String,
        nonce: UInt64,
        isMainnet: Bool,
        signatureChainId: UInt64 = defaultSignatureChainId
    ) throws -> HLUserSignedAction {
        let address = try HLAddress.bytes(builder)
        let chain = isMainnet ? "Mainnet" : "Testnet"
        let chainIdHex = "0x" + String(signatureChainId, radix: 16)
        let action = HLValue.object([
            ("type", .string("approveBuilderFee")),
            ("signatureChainId", .string(chainIdHex)),
            ("hyperliquidChain", .string(chain)),
            ("maxFeeRate", .string(maxFeeRate)),
            ("builder", .string("0x" + address.hexString)),
            ("nonce", .uint(nonce))
        ])
        let typed = HLTypedData(
            domain: .userSigned(signatureChainId: signatureChainId),
            primaryType: "HyperliquidTransaction:ApproveBuilderFee",
            fields: [
                HLTypedField(name: "hyperliquidChain", value: .string(chain)),
                HLTypedField(name: "maxFeeRate", value: .string(maxFeeRate)),
                HLTypedField(name: "builder", value: .address(address)),
                HLTypedField(name: "nonce", value: .uint64(nonce))
            ]
        )
        return HLUserSignedAction(action: action, typedData: typed, nonce: nonce)
    }
}

// MARK: - Wire number formatting

enum HLWireFormatError: Error, Equatable {
    /// More than 8 decimals: the SDK's `float_to_wire` raises rather than round.
    case precisionLoss
}

enum HLWireFormat {
    /// Plain decimal, no exponent, no trailing zeros ("30000", "0.001"),
    /// matching the Python SDK's `float_to_wire`. The venue normalises numbers
    /// before hashing, so "30000.0" signed client-side would not verify.
    static func decimalString(_ value: Decimal) -> String {
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 8, .plain)
        if rounded.isZero { return "0" }
        let text = NSDecimalNumber(decimal: rounded).stringValue
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// `decimalString` for a value that goes on the wire: like the Python
    /// SDK's `float_to_wire`, it refuses a value that does not survive 8
    /// decimals instead of silently signing a rounded one.
    static func wire(_ value: Decimal) throws -> String {
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 8, .plain)
        guard rounded == value else { throw HLWireFormatError.precisionLoss }
        return decimalString(value)
    }

    /// Size rounded DOWN to the asset's `szDecimals`.
    static func size(_ value: Decimal, szDecimals: Int) -> Decimal {
        round(value, scale: szDecimals, mode: .down)
    }

    /// Perp price rule: at most 5 significant figures and at most
    /// `6 - szDecimals` decimals. Mirrors the Python SDK's
    /// `round(float(f"{px:.5g}"), 6 - szDecimals)`, ties to even like Python.
    static func price(_ value: Decimal, szDecimals: Int) -> Decimal {
        guard value > 0 else { return 0 }
        let maxDecimals = max(0, 6 - szDecimals)
        let magnitude = Int(floor(log10(NSDecimalNumber(decimal: value).doubleValue)))
        let significantScale = 4 - magnitude
        let fiveSignificant = round(value, scale: significantScale, mode: .bankers)
        return round(fiveSignificant, scale: maxDecimals, mode: .bankers)
    }

    /// Aggressive IOC price for a "market" order: mid ± slippage, then rounded to a valid tick.
    static func marketPrice(mid: Decimal, isBuy: Bool, slippage: Decimal, szDecimals: Int) -> Decimal {
        let raw = isBuy ? mid * (1 + slippage) : mid * (1 - slippage)
        return price(raw, szDecimals: szDecimals)
    }

    private static func round(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var copy = value
        var result = Decimal()
        NSDecimalRound(&result, &copy, scale, mode)
        return result
    }
}
