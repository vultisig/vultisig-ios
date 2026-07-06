//
//  RippleService.swift
//  VultisigApp
//

import Foundation
import WalletCore
import BigInt
import OSLog

enum RippleFee {
    /// XRPL reference (base) fee under no load.
    static let referenceFeeDrops = 10
    /// Margin applied to the open-ledger cost to survive escalation while the
    /// TSS devices sign.
    static let safetyMultiplier = BigInt(2)
    /// Upper bound; comfortably covers fee escalation under load while keeping
    /// the cost negligible (0.002 XRP).
    static let maxFeeDrops = 2000

    /// Derives a fee (in drops) from the server's reported load.
    ///
    /// The open-ledger cost is `base_fee * load_factor / load_base`. We apply a
    /// safety multiplier so the transaction survives further escalation during
    /// the TSS signing window, then clamp to `[referenceFeeDrops, maxFeeDrops]`.
    static func recommendedFee(baseFee: Int?, loadFactor: Int?, loadBase: Int?) -> BigInt {
        let base = BigInt(baseFee ?? referenceFeeDrops)
        let factor = BigInt(loadFactor ?? 1)
        let divisor = BigInt(max(loadBase ?? 1, 1))

        let openLedgerFee = max(base, base * factor / divisor)
        let recommended = openLedgerFee * safetyMultiplier
        return min(max(recommended, BigInt(referenceFeeDrops)), BigInt(maxFeeDrops))
    }
}

class RippleService {

    static let shared = RippleService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "ripple-service")
    private let httpClient: HTTPClientProtocol = HTTPClient()

    /// Resolves the Ripple custom RPC override. Injected so the API values are
    /// built from a dependency rather than a global reach-in; resolution happens
    /// per request inside `api(_:)` so a runtime override change is picked up
    /// live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    init(resolver: RPCEndpointResolving = CustomRPCStore.shared) {
        self.resolver = resolver
    }

    /// The override-aware XRPL host. Falls back to the default host when no
    /// override is set.
    private var resolvedHost: URL {
        resolver.resolvedURL(for: .ripple, default: RippleAPI.defaultHost)
    }

    /// Builds a pure `RippleAPI` value with the resolved host baked in. The
    /// `TargetType` itself never consults the resolver.
    private func api(_ endpoint: RippleAPI.Endpoint) -> RippleAPI {
        RippleAPI(endpoint, host: resolvedHost)
    }

    func broadcastTransaction(_ hex: String) async throws -> String {
        let response = try await httpClient.request(
            api(.submit(txBlob: hex)),
            responseType: RippleSubmitResponse.self
        )

        let result = response.data.result

        // `tx_json.hash` is the deterministic hash of the exact blob we
        // submitted; XRPL echoes it back regardless of the engine result. Track
        // that hash even when the engine result isn't tesSUCCESS — tec* results
        // are applied on-chain, and for a tef/tem/ter/tel rejection the status
        // poller resolves the real outcome from this hash and surfaces the error
        // on screen. The bug this guards against is returning the engine error
        // *message* as the txid; a missing hash means we have nothing to track,
        // so surface the engine result/message as the failure instead of
        // persisting an empty string as a fake success.
        guard let hash = result?.txJson?.hash, !hash.isEmpty else {
            throw RippleBroadcastError.broadcastFailed(
                code: result?.engineResult ?? "unknown",
                message: result?.engineResultMessage
            )
        }
        return hash
    }

    func getBalance(address: String) async throws -> String {
        async let accountInfoTask = fetchAccountsInfo(for: address)
        async let serverStateTask = fetchServerState()

        let (accountInfo, serverState) = try await (accountInfoTask, serverStateTask)

        guard let totalBalanceStr = accountInfo?.result?.accountData?.balance,
              let totalBalance = BigInt(totalBalanceStr) else {
            return "0"
        }

        let ownerCount = BigInt(accountInfo?.result?.accountData?.ownerCount ?? 0)
        let reservedBase = BigInt(serverState?.result?.state?.validatedLedger?.reserveBase ?? 1000000)
        let reserveInc = BigInt(serverState?.result?.state?.validatedLedger?.reserveInc ?? 200000)

        let reservedBalance = reservedBase + (ownerCount * reserveInc)
        let availableBalance = max(totalBalance - reservedBalance, BigInt(0))

        return availableBalance.description
    }

    /// Resolves the fee (in drops) for an XRPL Payment.
    ///
    /// The XRPL reference fee is 10 drops; servers escalate it under load via
    /// `load_factor / load_base`. We compute the current open-ledger cost and
    /// apply a safety multiplier so the transaction survives fee escalation
    /// during the (up to 5 min) TSS signing window, then clamp to a sane
    /// ceiling. Any failure falls back to that ceiling so a send is never
    /// blocked on the fee lookup.
    func fetchFee() async -> BigInt {
        do {
            let state = try await fetchServerState()?.result?.state
            return RippleFee.recommendedFee(
                baseFee: state?.validatedLedger?.baseFee,
                loadFactor: state?.loadFactor,
                loadBase: state?.loadBase
            )
        } catch {
            logger.error("fetchFee: falling back to ceiling: \(error.localizedDescription)")
            return BigInt(RippleFee.maxFeeDrops)
        }
    }

    func fetchServerState() async throws -> RippleServerStateResponse? {
        do {
            let response = try await httpClient.request(
                api(.serverState),
                responseType: RippleServerStateResponse.self
            )
            return response.data
        } catch {
            logger.error("fetchServerState: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchAccountsInfo(for walletAddress: String) async throws -> RippleAccountResponse? {
        do {
            let response = try await httpClient.request(
                api(.accountInfo(account: walletAddress)),
                responseType: RippleAccountResponse.self
            )
            return response.data
        } catch {
            logger.error("fetchAccountsInfo: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Destination-tag requirement (RequireDest)

    /// AccountRoot `lsfRequireDestTag` flag: the account refuses payments
    /// without a destination tag. Reference: xrpl.org AccountRoot flags.
    static let lsfRequireDestTag = 0x00020000

    /// Maps an `account_info` result onto a destination-tag requirement.
    /// Pure so tests can pin the classification without the network.
    static func classifyDestinationTagRequirement(result: RippleAccountResponse.Result?) -> RippleDestinationTagRequirement {
        if result?.error == "actNotFound" {
            // Unfunded destination: no AccountRoot exists, so it cannot set
            // the flag. (Whether the send can fund it is the reserve
            // check's concern, not this gate's.)
            return .accountNotFound
        }
        guard let flags = result?.accountData?.flags else {
            return .unknown
        }
        return (flags & lsfRequireDestTag) != 0 ? .required : .notRequired
    }

    /// Looks up whether `address` requires a destination tag. Never throws:
    /// lookup failures classify as `.unknown` so the caller can decide the
    /// fail-open/fail-closed posture explicitly.
    func fetchDestinationTagRequirement(for address: String) async -> RippleDestinationTagRequirement {
        do {
            let response = try await fetchAccountsInfo(for: address)
            return Self.classifyDestinationTagRequirement(result: response?.result)
        } catch {
            logger.error("fetchDestinationTagRequirement: \(error.localizedDescription)")
            return .unknown
        }
    }
}

/// Whether an XRPL destination requires a destination tag on incoming
/// payments (AccountRoot `lsfRequireDestTag`).
enum RippleDestinationTagRequirement: Equatable {
    case required
    case notRequired
    /// Destination account doesn't exist on-ledger (`actNotFound`).
    case accountNotFound
    /// Lookup failed or returned an unrecognized shape.
    case unknown
}

enum RippleBroadcastError: Error, LocalizedError {
    case broadcastFailed(code: String, message: String?)

    var errorDescription: String? {
        switch self {
        case let .broadcastFailed(code, message):
            if let message, !message.isEmpty {
                return "Ripple broadcast failed (\(code)): \(message)"
            }
            return "Ripple broadcast failed (\(code))"
        }
    }
}

struct RippleAccountResponse: Codable {
    let result: Result?

    struct Result: Codable {
        let accountData: AccountData?
        let ledgerCurrentIndex: Int?
        let queueData: QueueData?
        let status: String?
        let validated: Bool?
        /// JSON-RPC error code string, e.g. `actNotFound` for accounts that
        /// don't exist on-ledger. Previously undecoded — such responses
        /// decoded as all-nil.
        let error: String?

        enum CodingKeys: String, CodingKey {
            case accountData = "account_data"
            case ledgerCurrentIndex = "ledger_current_index"
            case queueData = "queue_data"
            case status
            case validated
            case error
        }
    }

    struct AccountData: Codable {
        let account: String?
        let balance: String?
        let flags: Int?
        let ledgerEntryType: String?
        let ownerCount: Int?
        let previousTxnID: String?
        let previousTxnLgrSeq: Int?
        let sequence: Int?
        let index: String?

        enum CodingKeys: String, CodingKey {
            case account = "Account"
            case balance = "Balance"
            case flags = "Flags"
            case ledgerEntryType = "LedgerEntryType"
            case ownerCount = "OwnerCount"
            case previousTxnID = "PreviousTxnID"
            case previousTxnLgrSeq = "PreviousTxnLgrSeq"
            case sequence = "Sequence"
            case index
        }
    }

    struct QueueData: Codable {
        let authChangeQueued: Bool?
        let highestSequence: Int?
        let lowestSequence: Int?
        let maxSpendDropsTotal: String?
        let transactions: [Transaction]?
        let txnCount: Int?

        enum CodingKeys: String, CodingKey {
            case authChangeQueued = "auth_change_queued"
            case highestSequence = "highest_sequence"
            case lowestSequence = "lowest_sequence"
            case maxSpendDropsTotal = "max_spend_drops_total"
            case transactions
            case txnCount = "txn_count"
        }
    }

    struct Transaction: Codable {
        let authChange: Bool?
        let fee: String?
        let feeLevel: String?
        let maxSpendDrops: String?
        let seq: Int?
        let lastLedgerSequence: Int?

        enum CodingKeys: String, CodingKey {
            case authChange = "auth_change"
            case fee
            case feeLevel = "fee_level"
            case maxSpendDrops = "max_spend_drops"
            case seq
            case lastLedgerSequence = "LastLedgerSequence"
        }
    }
}

struct RippleServerStateResponse: Codable {
    let result: Result?

    struct Result: Codable {
        let state: State?

        enum CodingKeys: String, CodingKey {
            case state
        }
    }

    struct State: Codable {
        let loadBase: Int?
        let loadFactor: Int?
        let validatedLedger: ValidatedLedger?

        enum CodingKeys: String, CodingKey {
            case loadBase = "load_base"
            case loadFactor = "load_factor"
            case validatedLedger = "validated_ledger"
        }
    }

    struct ValidatedLedger: Codable {
        let baseFee: Int?
        let reserveBase: Int?
        let reserveInc: Int?

        enum CodingKeys: String, CodingKey {
            case baseFee = "base_fee"
            case reserveBase = "reserve_base"
            case reserveInc = "reserve_inc"
        }
    }
}
