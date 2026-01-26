//
//  CosmosTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

enum CosmosTransactionStatusAPI: TargetType {
    case getTransactionStatus(txHash: String, chain: Chain)

    var baseURL: URL {
        switch self {
        case .getTransactionStatus(_, let chain):
            return URL(string: getBaseURL(for: chain))!
        }
    }

    var path: String {
        switch self {
        case .getTransactionStatus(let txHash, _):
            return "/cosmos/tx/v1beta1/txs/\(txHash)"
        }
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        .requestPlain
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }

    private func getBaseURL(for chain: Chain) -> String {
        switch chain {
        case .thorChain:
            return "https://thornode.ninerealms.com"
        case .thorChainStagenet:
            return "https://testnet.thornode.thorchain.info"
        case .mayaChain:
            return "https://mayanode.mayachain.info"
        case .gaiaChain:
            return "https://cosmos-rest.publicnode.com"
        case .kujira:
            return "https://kujira-rest.publicnode.com"
        case .osmosis:
            return "https://osmosis-rest.publicnode.com"
        case .terra:
            return "https://terra-lcd.publicnode.com"
        case .terraClassic:
            return "https://terra-classic-lcd.publicnode.com"
        case .dydx:
            return "https://dydx-rest.publicnode.com"
        case .noble:
            return "https://api.noble.strange.love"
        case .akash:
            return "https://akash-rest.publicnode.com"
        default:
            return "https://cosmos-rest.publicnode.com"
        }
    }
}
