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
}

extension QBTCChainAPI: TargetType {
    var baseURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: Endpoint.qbtcRestBaseURL)!
    }

    var path: String {
        switch self {
        case .authAccount(let address):
            return "/cosmos/auth/v1beta1/accounts/\(address)"
        case .latestBlock:
            return "/cosmos/base/tendermint/v1beta1/blocks/latest"
        case .params(let name):
            return "/qbtc/v1/params/\(name)"
        }
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        .requestPlain
    }

    var headers: [String: String]? {
        nil
    }

    /// Auth-account is the only endpoint where 404 is expected (fresh
    /// account) and must be accepted by the caller, not raised as an
    /// error. The other two use default success-only validation.
    var validationType: ValidationType {
        switch self {
        case .authAccount:
            return .customCodes(Array(200...299) + [404])
        case .latestBlock, .params:
            return .successCodes
        }
    }
}
