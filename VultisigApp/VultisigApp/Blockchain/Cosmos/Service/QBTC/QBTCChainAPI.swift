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
    case latestBlock
    case params(name: String)
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
        case .latestBlock:
            return "/cosmos/base/tendermint/v1beta1/blocks/latest"
        case .params(let name):
            return "/qbtc/v1/params/\(name)"
        case .broadcastTx:
            return "/cosmos/tx/v1beta1/txs"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .authAccount, .latestBlock, .params:
            return .get
        case .broadcastTx:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .authAccount, .latestBlock, .params:
            return .requestPlain
        case .broadcastTx(let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .broadcastTx:
            return ["Content-Type": "application/json"]
        case .authAccount, .latestBlock, .params:
            return nil
        }
    }

    /// `authAccount` accepts 404 as fresh-account; `broadcastTx` accepts
    /// 4xx so the caller can inspect the chain's `tx_response` and detect
    /// idempotent replays via the `"tx already exists in cache"` body.
    var validationType: ValidationType {
        switch self {
        case .authAccount:
            return .customCodes(Array(200...299) + [404])
        case .latestBlock, .params:
            return .successCodes
        case .broadcastTx:
            return .customCodes(Array(200...299) + Array(400...499))
        }
    }
}
