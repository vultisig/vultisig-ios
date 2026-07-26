//
//  THORChainTransactionStatusAPI.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

enum THORChainTransactionStatusAPI: TargetType {
    case getActions(txHash: String, chain: Chain)

    var baseURL: URL {
        switch self {
        case .getActions(_, let chain):
            let urlString: String
            if chain == .mayaChain {
                urlString = Endpoint.mayachainMidgard
            } else if chain == .thorChainChainnet {
                urlString = "https://chainnet-thornode.thorchain.network"
            } else if chain == .thorChainStagenet {
                urlString = Endpoint.thorchainMidgardStagenet
            } else {
                urlString = Endpoint.thorchainMidgard
            }
            return URL(string: urlString)!
        }
    }

    var path: String {
        "/v2/actions"
    }

    var method: HTTPMethod {
        .get
    }

    var task: HTTPTask {
        switch self {
        case .getActions(let txHash, _):
            // Query actions by transaction ID, normalized to Midgard's convention.
            let params: [String: String] = ["txid": Self.midgardTxid(from: txHash)]
            return .requestParameters(params, .urlEncoding)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }

    /// Midgard keys every chain's txid as uppercase hex with NO `0x` prefix.
    ///
    /// THORChain- and Cosmos-native hashes already satisfy that, which is why
    /// they matched as-is; EVM hashes arrive `0x`-prefixed and lowercase, so
    /// without this an L1-sourced order's `?txid=` lookup returns nothing and
    /// the order never resolves. Idempotent for an already-normalized hash:
    /// there is no `0x` to strip, and uppercasing hex digits is a no-op — so it
    /// is correct to apply for every caller, native or EVM.
    private static func midgardTxid(from txHash: String) -> String {
        var hash = txHash
        if hash.hasPrefix("0x") || hash.hasPrefix("0X") {
            hash.removeFirst(2)
        }
        return hash.uppercased()
    }
}
