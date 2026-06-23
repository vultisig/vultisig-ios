//
//  QBTCChainAPI.swift
//  VultisigApp
//
//  TargetType for the QBTC chain REST endpoints. Distinct from the proof
//  service (QBTCProofServiceAPI) — this hits the chain itself for the
//  claim-flow gates (kill-switch params, per-UTXO state) and the x/gov
//  governance reads (proposals, tally, votes, params).
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

    // MARK: - Governance (x/gov v1)
    //
    // Queried with gov *v1* (richer proposal shape: messages[], title,
    // summary). The vote message itself stays at gov v1beta1 — see
    // QBTCHelper.

    /// List proposals, optionally filtered by `PROPOSAL_STATUS_*` and capped
    /// by `pagination.limit`.
    case govProposals(status: String?, limit: Int)
    /// Single proposal detail.
    case govProposal(id: UInt64)
    /// Live tally for an active proposal.
    case govTally(id: UInt64)
    /// The voter's recorded vote on a proposal. 404 ⇒ has not voted.
    case govVote(id: UInt64, voter: String)
    /// Gov params (`voting` / `tallying` / `deposit`).
    case govParams(type: String)
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
        case .govProposals:
            return "/cosmos/gov/v1/proposals"
        case .govProposal(let id):
            return "/cosmos/gov/v1/proposals/\(id)"
        case .govTally(let id):
            return "/cosmos/gov/v1/proposals/\(id)/tally"
        case .govVote(let id, let voter):
            return "/cosmos/gov/v1/proposals/\(id)/votes/\(voter)"
        case .govParams(let type):
            return "/cosmos/gov/v1/params/\(type)"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch self {
        case .govProposals(let status, let limit):
            var parameters: [String: Any] = ["pagination.limit": limit]
            if let status, !status.isEmpty {
                parameters["proposal_status"] = status
            }
            return .requestParameters(parameters, .urlEncoding)
        default:
            return .requestPlain
        }
    }

    var headers: [String: String]? { nil }

    /// `utxo` and `govVote` accept 404 — a not-yet-indexed UTXO and a
    /// proposal the voter hasn't voted on are both normal states the caller
    /// handles (un-claimable / "not voted") rather than errors.
    var validationType: ValidationType {
        switch self {
        case .utxo, .govVote:
            return .customCodes(Array(200...299) + [404])
        case .params, .govProposals, .govProposal, .govTally, .govParams:
            return .successCodes
        }
    }
}
