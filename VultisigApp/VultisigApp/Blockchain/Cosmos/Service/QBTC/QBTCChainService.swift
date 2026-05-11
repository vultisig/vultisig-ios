//
//  QBTCChainService.swift
//  VultisigApp
//
//  Reads QBTC chain state needed by the claim-flow gates:
//  - the `ClaimWithProofDisabled` kill-switch on the chain params.
//  - per-UTXO `entitled_amount` to filter the claimable set.
//
//  The cosmos auth/account/broadcast paths used to assemble a
//  `MsgClaimWithProof` on the client side are GONE under qbtc#158:
//  the proof service signs and broadcasts the tx itself.
//
//  Mirrors vultisig-sdk/.../getClaimWithProofDisabled.ts.
//

import Foundation
import OSLog

enum QBTCChainServiceError: LocalizedError {
    case invalidParamValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidParamValue(let raw):
            return "Invalid QBTC param value: \(raw)"
        }
    }
}

/// Response shape for the kill-switch param query.
/// `/cosmos/params/v1beta1/params?subspace=qbtc&key=ClaimWithProofDisabled`.
struct QBTCParamResponse: Codable {
    let param: Param

    struct Param: Codable {
        let key: String
        let value: String
    }
}

final class QBTCChainService {
    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-chain")

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
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

    // MARK: - Pure helpers (testable without network)

    /// Parses the kill-switch param value. Mirrors SDK behaviour:
    /// throws on non-numeric, returns `value > 0`.
    static func parseDisabledFlag(_ raw: String) throws -> Bool {
        guard let parsed = Int(raw) else {
            throw QBTCChainServiceError.invalidParamValue(raw)
        }
        return parsed > 0
    }

}
