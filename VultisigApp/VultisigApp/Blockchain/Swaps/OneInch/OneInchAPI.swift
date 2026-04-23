//
//  OneInchAPI.swift
//  VultisigApp
//

import Foundation

enum OneInchAPI: TargetType {
    case swap(chain: String, params: SwapParams)
    case tokens(chain: Int)

    struct SwapParams {
        let source: String
        let destination: String
        let amount: String
        let from: String
        let slippage: String
        let referrer: String
        /// Set to 0 when the user hasn't opted into the affiliate fee; the
        /// Vultisig proxy still expects the param to be present.
        let fee: Double
    }

    private static let vultisigProxyBaseURL = URL(string: "https://api.vultisig.com")!

    var baseURL: URL { Self.vultisigProxyBaseURL }

    var path: String {
        switch self {
        case .swap(let chain, _):
            return "/1inch/swap/v6.1/\(chain)/swap"
        case .tokens(let chain):
            return "/1inch/swap/v6.0/\(chain)/tokens"
        }
    }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch self {
        case .swap(_, let params):
            return .requestParameters([
                "src": params.source,
                "dst": params.destination,
                "amount": params.amount,
                "from": params.from,
                "slippage": params.slippage,
                "includeGas": "true",
                "disableEstimate": "true",
                "referrer": params.referrer,
                "fee": params.fee
            ], .urlEncoding)
        case .tokens:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        ["accept": "application/json"]
    }
}

// MARK: - Response types

struct OneInchTokensResponse: Decodable {
    let tokens: [String: OneInchToken]
}
