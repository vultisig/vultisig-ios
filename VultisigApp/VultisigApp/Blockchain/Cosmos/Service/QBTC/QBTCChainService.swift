//
//  QBTCChainService.swift
//  VultisigApp
//
//  Reads QBTC chain state needed to assemble a claim transaction:
//  - auth account info (404 ⇒ fresh account)
//  - latest block (height + time → timeoutNs)
//  - the ClaimWithProofDisabled kill-switch
//
//  Mirrors vultisig-sdk/.../getQbtcAccountInfo.ts and getClaimWithProofDisabled.ts.
//

import Foundation
import OSLog

enum QBTCChainServiceError: LocalizedError {
    case invalidLatestBlockTime(String)
    case invalidParamValue(String)
    case broadcastFailed(rawLog: String, code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidLatestBlockTime(let raw):
            return "Could not parse QBTC latest block time: \(raw)"
        case .invalidParamValue(let raw):
            return "Invalid QBTC param value: \(raw)"
        case .broadcastFailed(let rawLog, let code):
            return "QBTC broadcast failed (code \(code)): \(rawLog)"
        }
    }
}

/// Cosmos broadcast `tx_response` shape — minimal subset we care about.
struct QBTCBroadcastResponse: Codable {
    let txResponse: TxResponse?

    struct TxResponse: Codable {
        let txhash: String?
        let code: Int?
        let rawLog: String?

        enum CodingKeys: String, CodingKey {
            case txhash
            case code
            case rawLog = "raw_log"
        }
    }

    enum CodingKeys: String, CodingKey {
        case txResponse = "tx_response"
    }
}

final class QBTCChainService {
    /// 10 minutes, in nanoseconds. Matches the SDK
    /// (`getQbtcAccountInfo.ts:36`).
    static let claimTimeoutNs: UInt64 = 600_000_000_000

    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-chain")
    private let timestampFormatter: ISO8601DateFormatter

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
        self.timestampFormatter = ISO8601DateFormatter()
        self.timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Fetches the account info plus the latest block, parallelised.
    ///
    /// Fresh-account handling (no existing account at this address): the chain's
    /// `FreeClaimDecorator` will atomically increment the global counter and
    /// assign the next number when the claim broadcast hits the ante stack.
    /// SigVerify then reconstructs the SignDoc with that assigned number, so we
    /// must sign with the same prediction now. We query the highest-numbered
    /// existing account and use `highest + 1`.
    ///
    /// Race window: another claim could increment the counter between our query
    /// and the broadcast. If that happens the broadcast fails with code 4
    /// (`signature verification failed`) and the user retries — the retry sees
    /// a higher counter and predicts correctly. Stopgap until the chain ships a
    /// custom sigverify decorator that accepts `account_number=0` for fresh
    /// claim accounts; tracked as the cleaner long-term fix.
    func getAccountInfoForClaim(qbtcAddress: String) async throws -> QBTCClaimAccountInfo {
        async let accountTask = fetchAuthAccount(address: qbtcAddress)
        async let blockTask = fetchLatestBlock()

        let (account, block) = try await (accountTask, blockTask)

        let height = UInt64(block.block.header.height) ?? 0
        let timeoutNs = try computeTimeoutNs(blockTime: block.block.header.time)

        let accountNumber: UInt64
        let sequence: UInt64
        if let account {
            // Existing account — read the chain-assigned values directly.
            accountNumber = UInt64(account.accountNumber) ?? 0
            sequence = UInt64(account.sequence) ?? 0
        } else {
            // Fresh account — predict the assigned number.
            accountNumber = try await predictAssignedAccountNumber()
            sequence = 0
            logger.debug("Predicted fresh-account number=\(accountNumber, privacy: .public) for \(qbtcAddress, privacy: .public)")
        }

        return QBTCClaimAccountInfo(
            accountNumber: accountNumber,
            sequence: sequence,
            latestBlockHeight: height,
            timeoutNs: timeoutNs
        )
    }

    /// Hits `/cosmos/auth/v1beta1/accounts?pagination.limit=1000` and scans the
    /// page for the highest assigned `account_number`, returning `highest + 1`
    /// as the predicted assignment for the next `FreeClaimDecorator` ante run.
    ///
    /// The endpoint paginates by store key (address bytes), not by
    /// `account_number`, so we have to scan every entry on the page. Both
    /// `BaseAccount` and `ModuleAccount` share the global account-number
    /// counter, so both contribute to the max. Returns `0` if no accounts come
    /// back (effectively genesis — should never happen on QBTC testnet, which
    /// has at least the fee_collector module account).
    ///
    /// If the chain returns a non-empty `next_key`, log a warning — we're only
    /// scanning the first 1000 accounts and the prediction may be wrong, which
    /// surfaces to the user as `code 4 signature verification failed` and a
    /// retry. This is a stopgap until the chain ships a sigverify decorator
    /// that accepts `account_number=0` for fresh claim accounts.
    private func predictAssignedAccountNumber() async throws -> UInt64 {
        let response = try await httpClient.request(
            QBTCChainAPI.latestAccount,
            responseType: QBTCAccountsListResponse.self
        )
        let highest = response.data.accounts
            .compactMap { UInt64($0.accountNumber) }
            .max() ?? 0
        if let nextKey = response.data.pagination?.nextKey, !nextKey.isEmpty {
            logger.warning("QBTC accounts list has more pages (next_key present); prediction may underestimate max account_number=\(highest, privacy: .public)")
        }
        logger.debug("QBTC predicted assigned account_number=\(highest + 1, privacy: .public) from \(response.data.accounts.count, privacy: .public) accounts")
        return highest + 1
    }

    /// Fetches the chain's claim eligibility for a single UTXO. 404 → not
    /// indexed by bifrost yet; `entitled_amount == 0` → already claimed;
    /// otherwise claimable with the chain's `entitled_amount` (which the
    /// chain will mint exactly, even if blockchair reports a different
    /// `value`).
    func fetchUtxoStatus(txid: String, vout: UInt32) async throws -> QBTCUtxoStatus {
        let response = try await httpClient.request(QBTCChainAPI.utxo(txid: txid, vout: vout))
        if response.response.statusCode == 404 {
            return .notIndexed
        }
        let decoded = try JSONDecoder().decode(QBTCUtxoQueryResponse.self, from: response.data)
        let entitled = UInt64(decoded.utxo.entitledAmount) ?? 0
        if entitled == 0 {
            return .claimed
        }
        return .claimable(entitledAmount: entitled)
    }

    /// Fans out per-UTXO chain-state queries in parallel and keeps only
    /// claimable entries. The displayed amount is replaced with the chain's
    /// `entitled_amount` so totals match what will actually be minted.
    ///
    /// Fail-open on transient errors (network, 5xx, decode failure): the
    /// UTXO is kept with its original blockchair amount. Hiding a UTXO the
    /// user can see in their BTC wallet is worse than letting the broadcast
    /// reject it. Only definite "claimed" / "not indexed" responses filter.
    func filterClaimable(_ utxos: [ClaimableUtxo]) async -> [ClaimableUtxo] {
        guard !utxos.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, ClaimableUtxo?).self) { group in
            for (index, utxo) in utxos.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, utxo) }
                    do {
                        let status = try await self.fetchUtxoStatus(txid: utxo.txid, vout: utxo.vout)
                        switch status {
                        case .claimable(let entitled):
                            return (index, ClaimableUtxo(txid: utxo.txid, vout: utxo.vout, amount: entitled))
                        case .claimed:
                            self.logger.debug("filtering claimed UTXO \(utxo.txid, privacy: .public):\(utxo.vout, privacy: .public)")
                            return (index, nil)
                        case .notIndexed:
                            self.logger.debug("filtering not-indexed UTXO \(utxo.txid, privacy: .public):\(utxo.vout, privacy: .public)")
                            return (index, nil)
                        }
                    } catch {
                        self.logger.warning("UTXO status query failed for \(utxo.txid, privacy: .public):\(utxo.vout, privacy: .public) — keeping as fail-open: \(error.localizedDescription)")
                        return (index, utxo)
                    }
                }
            }
            var collected: [(Int, ClaimableUtxo?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
                .sorted { $0.0 < $1.0 }
                .compactMap { $0.1 }
        }
    }

    /// Returns `true` iff the chain has the `ClaimWithProofDisabled`
    /// param set to a non-zero integer. Fail-closed callers should
    /// treat `nil` / errors as disabled too.
    func isClaimWithProofDisabled() async throws -> Bool {
        let response = try await httpClient.request(
            QBTCChainAPI.params(name: "ClaimWithProofDisabled"),
            responseType: QBTCParamResponse.self
        )
        return try Self.parseDisabledFlag(response.data.param.value)
    }

    /// Broadcasts a signed claim transaction. `txBytesBase64` is the
    /// base64-encoded `TxRaw`; `txHashHex` is the locally-computed hash
    /// (uppercased SHA-256 of the TxRaw — see `QBTCHelper.assembleClaimTxRaw`).
    /// Treats `"tx already exists in cache"` as idempotent success so a
    /// retry of an already-broadcast tx returns the same hash, mirroring
    /// `vultisig-sdk/.../broadcastClaimTx.ts:36-79`.
    func broadcastClaim(txBytesBase64: String, txHashHex: String) async throws -> String {
        let body = Self.makeBroadcastBody(txBytesBase64: txBytesBase64)
        let response = try await httpClient.request(
            QBTCChainAPI.broadcastTx(body: body),
            responseType: QBTCBroadcastResponse.self
        )
        return try Self.parseBroadcastResponse(response.data, txHashHex: txHashHex)
    }

    static func makeBroadcastBody(txBytesBase64: String) -> Data {
        // Hand-crafted JSON to exactly match `cosmos.tx.v1beta1.BroadcastTxRequest`.
        let json = "{\"tx_bytes\":\"\(txBytesBase64)\",\"mode\":\"BROADCAST_MODE_SYNC\"}"
        return Data(json.utf8)
    }

    /// Returns the tx hash on success or idempotent replay; throws on
    /// real broadcast failure.
    static func parseBroadcastResponse(_ response: QBTCBroadcastResponse, txHashHex: String) throws -> String {
        let code = response.txResponse?.code ?? 0
        let rawLog = response.txResponse?.rawLog ?? ""

        if code == 0 {
            return response.txResponse?.txhash ?? txHashHex
        }
        // Idempotent replay — the chain already has this tx in its
        // mempool / cache. Treat as success so retry-after-network-blip
        // doesn't surface as an error to the user.
        if rawLog.contains("tx already exists in cache") {
            return response.txResponse?.txhash ?? txHashHex
        }
        throw QBTCChainServiceError.broadcastFailed(rawLog: rawLog, code: code)
    }

    // MARK: - Pure helpers (testable without network)

    /// Parses the kill-switch param value. Mirrors SDK behaviour:
    /// throws on non-numeric, returns `value > 0`.
    static func parseDisabledFlag(_ raw: String) throws -> Bool {
        guard let parsed = Int(raw) else {
            throw QBTCChainServiceError.invalidParamValue(raw)
        }
        return parsed > 0
    }

    /// Converts an ISO-8601 block timestamp to a `timeoutNs = blockTimeNs + 10min`.
    /// Matches `vultisig-sdk/.../getQbtcAccountInfo.ts:33-36`.
    func computeTimeoutNs(blockTime: String) throws -> UInt64 {
        guard let date = parseIso8601(blockTime) else {
            throw QBTCChainServiceError.invalidLatestBlockTime(blockTime)
        }
        // Date.timeIntervalSince1970 is seconds (Double). Convert to ns.
        let blockTimeNsDouble = date.timeIntervalSince1970 * 1_000_000_000
        guard blockTimeNsDouble.isFinite, blockTimeNsDouble >= 0 else {
            throw QBTCChainServiceError.invalidLatestBlockTime(blockTime)
        }
        let blockTimeNs = UInt64(blockTimeNsDouble)
        return blockTimeNs + Self.claimTimeoutNs
    }

    // MARK: - Private

    /// Tries the formatter with fractional seconds first (chain timestamps
    /// usually carry them), then without — covers both `2026-04-29T12:00:00Z`
    /// and `2026-04-29T12:00:00.123456789Z`.
    private func parseIso8601(_ value: String) -> Date? {
        if let date = timestampFormatter.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    /// Returns the `account` field, or `nil` when the chain returns 404.
    private func fetchAuthAccount(address: String) async throws -> QBTCAuthAccountResponse.Account? {
        let response = try await httpClient.request(QBTCChainAPI.authAccount(address: address))
        let httpStatus = response.response.statusCode

        if httpStatus == 404 {
            logger.debug("QBTC auth/accounts returned 404 for \(address) — treating as fresh account")
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(QBTCAuthAccountResponse.self, from: response.data)
            return decoded.account
        } catch {
            // The chain occasionally returns `{}` for not-yet-funded accounts;
            // treat any decode failure on a 200 as fresh, rather than fatally
            // failing the claim flow.
            logger.warning("Could not decode QBTC auth/accounts payload — treating as fresh account: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchLatestBlock() async throws -> QBTCLatestBlockResponse {
        let response = try await httpClient.request(
            QBTCChainAPI.latestBlock,
            responseType: QBTCLatestBlockResponse.self
        )
        return response.data
    }
}
