//
//  QBTCChainAPI.swift
//  VultisigApp
//
//  TargetType for the QBTC chain REST endpoints used by the claim flow.
//  Distinct from the proof service (QBTCProofServiceAPI) — this hits the
//  chain itself for kill-switch params and per-UTXO state.
//
//  Post-qbtc#158: the proof service signs and broadcasts
//  `MsgClaimWithProof` directly, so the iOS-side `authAccount` /
//  `latestBlock` / `latestAccount` / `broadcastTx` endpoints are gone.
//

import Foundation

enum QBTCChainAPI {
    case params(name: String)
    /// Per-UTXO chain-state lookup. Used by the selection screen to drop
    /// already-claimed (`entitled_amount=0`) and not-indexed (404) UTXOs
    /// before the user picks them.
    case utxo(txid: String, vout: UInt32)
}

extension QBTCChainAPI: TargetType {
    var baseURL: URL {
        guard let url = URL(string: Endpoint.qbtcRestBaseURL) else {
            preconditionFailure("Invalid QBTC REST base URL: \(Endpoint.qbtcRestBaseURL)")
        }
        return url
    }

    var path: String {
        switch self {
        case .params(let name):
            return "/qbtc/v1/params/\(name)"
        case .utxo(let txid, let vout):
            return "/qbtc/v1/utxo/\(txid)/\(vout)"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask { .requestPlain }

    var headers: [String: String]? { nil }

    /// `utxo` accepts 404 — a not-yet-indexed UTXO is a normal state the
    /// caller handles by treating the UTXO as un-claimable.
    var validationType: ValidationType {
        switch self {
        case .utxo:
            return .customCodes(Array(200...299) + [404])
        case .params:
            return .successCodes
        }
    }
}
