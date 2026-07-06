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

    /// Direct HTTP client for the verify-by-hash `tx` lookup, which runs its
    /// own bespoke retry loop (see `resolveSubmitByHash`).
    private let httpClient: HTTPClientProtocol

    /// Executes requests with a bounded same-host retry on transient node
    /// errors (`amendmentBlocked` and the node-unavailable family). Because the
    /// resolved host is a load-balanced pool, a same-host retry routes to a
    /// different (healthy) backend — no fallback host list is needed.
    private let retrier: RippleRequestRetrier

    /// Resolves the Ripple custom RPC override. Injected so the API values are
    /// built from a dependency rather than a global reach-in; resolution happens
    /// per request inside `api(_:)` so a runtime override change is picked up
    /// live (the shared mirror updates without a relaunch).
    private let resolver: RPCEndpointResolving

    /// Backoff between `tx` lookups while resolving a verify-by-hash submit;
    /// injectable so tests run without delay.
    private let verifyByHashBackoff: Duration

    init(
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        httpClient: HTTPClientProtocol = HTTPClient(),
        sleep: @escaping RippleRequestRetrier.Sleeper = RippleRequestRetrier.defaultSleep,
        verifyByHashBackoff: Duration = .seconds(2)
    ) {
        self.resolver = resolver
        self.httpClient = httpClient
        self.retrier = RippleRequestRetrier(httpClient: httpClient, sleep: sleep)
        self.verifyByHashBackoff = verifyByHashBackoff
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
        let response = try await retrier.request(
            api(.submit(txBlob: hex)),
            responseType: RippleSubmitResponse.self
        )

        let result = response.result
        let disposition = RippleSubmitDisposition.classify(
            engineResult: result?.engineResult,
            engineResultMessage: result?.engineResultMessage,
            hash: result?.txJson?.hash
        )

        switch disposition {
        case .accepted(let hash):
            return hash
        case .verifyByHash(let code, let hash, let message):
            return try await resolveSubmitByHash(code: code, hash: hash, message: message)
        case .rejected(let code, let message):
            logger.error("broadcast rejected by XRPL: \(code, privacy: .public)")
            throw RippleBroadcastError.broadcastFailed(code: code, message: message)
        }
    }

    /// Resolves a submit whose engine result says the transaction may already
    /// be known to the network — a faster co-signing peer's broadcast of the
    /// same signed blob landed first, or the server queued it for a future
    /// ledger — by looking the echoed deterministic hash up with the `tx`
    /// method against the same (override-aware) node the submit went to.
    ///
    /// `txnNotFound` is retried with a short backoff because cluster nodes can
    /// lag a peer's submit by a few seconds; lookup errors count as failed
    /// attempts for the same reason (the lookup is a safety net and must not
    /// invent a new failure mode). If the transaction never shows up, the
    /// ORIGINAL engine code is thrown — an unverified duplicate must never be
    /// reported as a success.
    private func resolveSubmitByHash(code: String, hash: String?, message: String?) async throws -> String {
        guard let hash else {
            throw RippleBroadcastError.broadcastFailed(code: code, message: message)
        }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let response = try await httpClient.request(
                    api(.tx(hash: hash)),
                    responseType: RippleTransactionStatusResponse.self
                )

                switch RippleTxLookupOutcome.interpret(response.data) {
                case .validatedSuccess:
                    logger.info("\(code, privacy: .public) resolved as validated success: \(hash, privacy: .public)")
                    return hash
                case .pending:
                    // Known to the network and in flight — return the hash and
                    // let the status poller resolve the final outcome.
                    logger.info("\(code, privacy: .public) resolved as in-flight: \(hash, privacy: .public)")
                    return hash
                case .validatedFailure(let validatedCode):
                    // The transaction landed in a validated ledger with a final
                    // non-success result — surface that real code.
                    logger.error("\(code, privacy: .public) resolved as validated failure \(validatedCode, privacy: .public)")
                    throw RippleBroadcastError.broadcastFailed(
                        code: validatedCode,
                        message: "The transaction was included in a validated ledger but did not succeed."
                    )
                case .notFound:
                    break
                }
            } catch let error as RippleBroadcastError {
                throw error
            } catch {
                logger.warning("verify-by-hash lookup failed (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription, privacy: .public)")
            }

            if attempt < maxAttempts {
                do {
                    try await Task.sleep(for: verifyByHashBackoff)
                } catch {
                    logger.warning("verify-by-hash backoff interrupted: \(error.localizedDescription, privacy: .public)")
                    break
                }
            }
        }

        logger.error("verify-by-hash exhausted for \(code, privacy: .public): \(hash, privacy: .public) not found")
        throw RippleBroadcastError.broadcastFailed(code: code, message: message)
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
            return try await retrier.request(
                api(.serverState),
                responseType: RippleServerStateResponse.self
            )
        } catch {
            logger.error("fetchServerState: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchAccountsInfo(for walletAddress: String) async throws -> RippleAccountResponse? {
        do {
            return try await retrier.request(
                api(.accountInfo(account: walletAddress)),
                responseType: RippleAccountResponse.self
            )
        } catch {
            logger.error("fetchAccountsInfo: \(error.localizedDescription)")
            throw error
        }
    }
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
        /// Node-level error (e.g. `amendmentBlocked`) returned in an HTTP-200
        /// body. Distinct from `actNotFound`, which is a valid "unfunded
        /// account" outcome and is intentionally not retryable.
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
        /// Node-level error (e.g. `amendmentBlocked`) returned in an HTTP-200
        /// body when the backend can't serve `server_state`.
        let error: String?

        enum CodingKeys: String, CodingKey {
            case state
            case error
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

extension RippleAccountResponse: RippleRPCResponse {
    var rpcError: String? { result?.error }
}

extension RippleServerStateResponse: RippleRPCResponse {
    var rpcError: String? { result?.error }
}
