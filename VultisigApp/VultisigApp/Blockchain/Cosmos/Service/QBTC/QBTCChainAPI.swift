//
//  QBTCChainAPI.swift
//  VultisigApp
//
//  TargetType for the QBTC chain REST endpoints used by the claim flow.
//  Distinct from the proof service (QBTCProofServiceAPI) — this hits the
//  chain itself for account info, latest block, and chain params.
//

import Foundation

enum QBTCChainAPI {
    case authAccount(address: String)
    /// Lists auth accounts so the caller can scan for the highest assigned
    /// `account_number`. Used to predict the assigned number for first-claim
    /// flows where the user's account doesn't exist yet — the chain's
    /// `FreeClaimDecorator` will assign `highest + 1` at the next ante run,
    /// and we must sign the SignDoc with that value.
    ///
    /// Note: `pagination.reverse` here paginates by store key (address bytes),
    /// not by `account_number`, so reverse + limit=1 is useless — we have to
    /// scan the page and find max client-side.
    case latestAccount
    case latestBlock
    case params(name: String)
    /// Per-UTXO chain-state lookup. Used by the selection screen to drop
    /// already-claimed (`entitled_amount=0`) and not-indexed (404) UTXOs
    /// before the user picks them.
    case utxo(txid: String, vout: UInt32)
    case broadcastTx(body: Data)
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
        case .authAccount(let address):
            return "/cosmos/auth/v1beta1/accounts/\(address)"
        case .latestAccount:
            return "/cosmos/auth/v1beta1/accounts"
        case .latestBlock:
            return "/cosmos/base/tendermint/v1beta1/blocks/latest"
        case .params(let name):
            return "/qbtc/v1/params/\(name)"
        case .utxo(let txid, let vout):
            return "/qbtc/v1/utxo/\(txid)/\(vout)"
        case .broadcastTx:
            return "/cosmos/tx/v1beta1/txs"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .authAccount, .latestAccount, .latestBlock, .params, .utxo:
            return .get
        case .broadcastTx:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .authAccount, .latestBlock, .params, .utxo:
            return .requestPlain
        case .latestAccount:
            // 1000 is well above QBTC testnet's expected user-account count;
            // the helper warns if the chain still has a `next_key`, in which
            // case we'd be undercounting and the broadcast would fail with
            // `code 4 / signature verification failed`.
            return .requestParameters([
                "pagination.limit": "1000"
            ], .urlEncoding)
        case .broadcastTx(let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .broadcastTx:
            return ["Content-Type": "application/json"]
        case .authAccount, .latestAccount, .latestBlock, .params, .utxo:
            return nil
        }
    }

    /// `authAccount` and `utxo` accept 404 — fresh account / not-yet-indexed
    /// UTXO are normal states the caller handles. `broadcastTx` accepts 4xx
    /// so the caller can inspect the chain's `tx_response` and detect
    /// idempotent replays via the `"tx already exists in cache"` body.
    var validationType: ValidationType {
        switch self {
        case .authAccount, .utxo:
            return .customCodes(Array(200...299) + [404])
        case .latestAccount, .latestBlock, .params:
            return .successCodes
        case .broadcastTx:
            return .customCodes(Array(200...299) + Array(400...499))
        }
    }
}
