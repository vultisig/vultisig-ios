//
//  HyperliquidExchangeClient.swift
//  VultisigApp
//
//  The /exchange client, DRY-RUN ONLY. It builds the exact body the
//  Python SDK's `_post_action` would POST ({action, nonce, signature,
//  vaultAddress, expiresAfter}) and records it in a "would submit" log. There
//  is no network code in this file and no way to switch it on: a live client
//  is a separate, reviewed change.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "perps-exchange")

/// Hyperliquid keeps the 100 highest nonces per signer; a new one must be
/// unused and inside (now - 2d, now + 1d). Millisecond time, bumped so two
/// actions in the same millisecond (updateLeverage then order) never collide.
final class HLNonceSource: @unchecked Sendable {
    private let lock = NSLock()
    private var last: UInt64 = 0
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let now = UInt64(clock().timeIntervalSince1970 * 1000)
        last = max(now, last + 1)
        return last
    }

    /// Short replay window for L1 actions, as the spec's policy section asks:
    /// a signed-but-unsent order is dead after this.
    static let defaultExpiryMs: UInt64 = 60_000
}

/// The signature in the posted body. A vault signature only exists after the
/// shared keysign ceremony, which perps does not run yet, so dry runs carry the
/// digest the vault would sign instead.
enum HLExchangeSignature: Equatable, Sendable {
    /// Only a recovered-and-checked signature can be posted.
    case signed(VerifiedHLSignature)
    case pendingVaultKeysign(digest: Data)

    var wire: HLValue {
        switch self {
        case .signed(let verified):
            let signature = verified.signature
            // The SDK renders r/s with eth_utils `to_hex(int)`: no leading zeros.
            return .object([
                ("r", .string(Self.minimalHex(signature.r))),
                ("s", .string(Self.minimalHex(signature.s))),
                ("v", .int(Int64(signature.v)))
            ])
        case .pendingVaultKeysign(let digest):
            return .object([("pendingVaultKeysign", .string("0x" + digest.hexString))])
        }
    }

    static func minimalHex(_ hex: String) -> String {
        let digits = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let trimmed = digits.drop { $0 == "0" }
        return "0x" + (trimmed.isEmpty ? "0" : String(trimmed))
    }
}

/// One /exchange request, ready to post.
struct HLExchangeRequest: Equatable, Sendable {
    enum Kind: String, Sendable {
        case order, cancel, updateLeverage, updateIsolatedMargin, approveAgent, approveBuilderFee, withdraw3
    }

    let kind: Kind
    let action: HLValue
    let nonce: UInt64
    let vaultAddress: String?
    let expiresAfter: UInt64?
    let typedData: HLTypedData
    var signature: HLExchangeSignature

    var digest: Data { typedData.digest }

    /// The SDK's `_post_action` payload, keys in the same order. `vaultAddress`
    /// and `expiresAfter` are posted as null when unset, as the SDK does.
    var body: HLValue {
        .object([
            ("action", action),
            ("nonce", .uint(nonce)),
            ("signature", signature.wire),
            ("vaultAddress", vaultAddress.map { .string($0.lowercased()) } ?? .null),
            ("expiresAfter", expiresAfter.map { .uint($0) } ?? .null)
        ])
    }

    var jsonBody: String { body.jsonString }

    static func l1(
        _ kind: Kind,
        action: HLValue,
        nonce: UInt64,
        isMainnet: Bool,
        vaultAddress: String? = nil,
        expiresAfter: UInt64? = nil
    ) throws -> HLExchangeRequest {
        let typed = try HLActionHasher.l1TypedData(
            action: action, nonce: nonce, isMainnet: isMainnet, vaultAddress: vaultAddress, expiresAfter: expiresAfter
        )
        return HLExchangeRequest(
            kind: kind, action: action, nonce: nonce, vaultAddress: vaultAddress, expiresAfter: expiresAfter,
            typedData: typed, signature: .pendingVaultKeysign(digest: typed.digest)
        )
    }

    /// User-signed actions never carry `vaultAddress` or `expiresAfter`.
    static func userSigned(_ kind: Kind, _ signed: HLUserSignedAction) -> HLExchangeRequest {
        HLExchangeRequest(
            kind: kind, action: signed.action, nonce: signed.nonce, vaultAddress: nil, expiresAfter: nil,
            typedData: signed.typedData, signature: .pendingVaultKeysign(digest: signed.typedData.digest)
        )
    }

    /// The request the shared keysign flow would sign for this body.
    var signRequest: PerpsSignRequest {
        switch kind {
        case .approveAgent, .approveBuilderFee, .withdraw3:
            return .userSigned(HLUserSignedAction(action: action, typedData: typedData, nonce: nonce))
        default:
            return .l1(action: action, nonce: nonce, isMainnet: PerpsConfig.isMainnet, vaultAddress: vaultAddress, expiresAfter: expiresAfter)
        }
    }
}

struct HLDryRunEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date: Date
    /// The /exchange action type, or "sendFlow" for a transfer through the existing send flow.
    let kind: String
    let digest: String
    let json: String

    static func == (lhs: HLDryRunEntry, rhs: HLDryRunEntry) -> Bool { lhs.id == rhs.id }
}

enum HLExchangeResult: Equatable, Sendable {
    /// Nothing was sent. The body is what would have been posted.
    case dryRun(json: String)
}

/// Dry-run /exchange client. `submit` only logs.
@MainActor
final class HyperliquidExchangeDryRunClient: ObservableObject {
    static let shared = HyperliquidExchangeDryRunClient()
    static let endpoint = "POST https://api.hyperliquid.xyz/exchange"

    @Published private(set) var log: [HLDryRunEntry] = []
    let nonces = HLNonceSource()

    @discardableResult
    func submit(_ request: HLExchangeRequest) -> HLExchangeResult {
        let json = request.jsonBody
        let entry = HLDryRunEntry(date: Date(), kind: request.kind.rawValue, digest: "0x" + request.digest.hexString, json: json)
        log.insert(entry, at: 0)
        logger.info("[dry-run] would submit \(Self.endpoint, privacy: .public) \(json, privacy: .public)")
        return .dryRun(json: json)
    }

    func submit(_ requests: [HLExchangeRequest]) {
        requests.forEach { submit($0) }
    }

    /// A deposit is CCTP on Arbitrum, not an /exchange call. Logged so the dry
    /// run shows every step: the USDC authorization the vault would sign, and
    /// the burn parameters of the Arbitrum call.
    func recordDeposit(_ deposit: HLCctpDeposit) {
        let units = HLCctp.usdcUnits(deposit.amount)
        let json = "{\"chain\":\"arbitrum\",\"contract\":\"\(HLCctp.cctpExtensionArbitrum)\",\"function\":\"batchDepositForBurnWithAuth\","
            + "\"amount\":\(units),\"destinationDomain\":\(HLCctp.hyperEvmDomain),\"mintRecipient\":\"\(HLCctp.cctpForwarderHyperEvm)\","
            + "\"destinationCaller\":\"\(HLCctp.cctpForwarderHyperEvm)\",\"maxFee\":\(HLCctp.usdcUnits(HLCctp.forwardingFee)),"
            + "\"minFinalityThreshold\":\(HLCctp.fastFinalityThreshold),\"hookData\":\"0x\(deposit.hookData.hexString)\","
            + "\"hyperCoreRecipient\":\"\(deposit.tradingAddress)\",\"authorizationDigest\":\"0x\(deposit.authorization.digest.hexString)\"}"
        log.insert(HLDryRunEntry(date: Date(), kind: "cctpDeposit", digest: "0x" + deposit.authorization.digest.hexString, json: json), at: 0)
        logger.info("[dry-run] would deposit via CCTP \(json, privacy: .public)")
    }
}
