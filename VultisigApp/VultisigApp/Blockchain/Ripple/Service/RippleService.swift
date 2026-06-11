//
//  RippleService.swift
//  VultisigApp
//

import Foundation
import WalletCore
import BigInt
import OSLog

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

        enum CodingKeys: String, CodingKey {
            case accountData = "account_data"
            case ledgerCurrentIndex = "ledger_current_index"
            case queueData = "queue_data"
            case status
            case validated
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
        let validatedLedger: ValidatedLedger?

        enum CodingKeys: String, CodingKey {
            case validatedLedger = "validated_ledger"
        }
    }

    struct ValidatedLedger: Codable {
        let reserveBase: Int?
        let reserveInc: Int?

        enum CodingKeys: String, CodingKey {
            case reserveBase = "reserve_base"
            case reserveInc = "reserve_inc"
        }
    }
}
