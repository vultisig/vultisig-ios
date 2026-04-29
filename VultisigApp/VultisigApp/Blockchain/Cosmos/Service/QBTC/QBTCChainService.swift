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

    var errorDescription: String? {
        switch self {
        case .invalidLatestBlockTime(let raw):
            return "Could not parse QBTC latest block time: \(raw)"
        case .invalidParamValue(let raw):
            return "Invalid QBTC param value: \(raw)"
        }
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
    /// 404 on the auth endpoint MUST be treated as a fresh account
    /// (`accountNumber=0, sequence=0`) — the claim is often the first
    /// transaction the address ever sends.
    func getAccountInfoForClaim(qbtcAddress: String) async throws -> QBTCClaimAccountInfo {
        async let accountTask = fetchAuthAccount(address: qbtcAddress)
        async let blockTask = fetchLatestBlock()

        let (account, block) = try await (accountTask, blockTask)

        let height = UInt64(block.block.header.height) ?? 0
        let timeoutNs = try computeTimeoutNs(blockTime: block.block.header.time)

        let accountNumber = UInt64(account?.accountNumber ?? "0") ?? 0
        let sequence = UInt64(account?.sequence ?? "0") ?? 0

        return QBTCClaimAccountInfo(
            accountNumber: accountNumber,
            sequence: sequence,
            latestBlockHeight: height,
            timeoutNs: timeoutNs
        )
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
