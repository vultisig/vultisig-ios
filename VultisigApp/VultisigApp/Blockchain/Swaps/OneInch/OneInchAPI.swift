//
//  OneInchAPI.swift
//  VultisigApp
//

import Foundation

enum OneInchAPI: TargetType {
    case swap(chain: String, params: SwapParams)
    case tokens(chain: Int)
    /// `/balance/v1.2/{chain}/balances/{address}` — returns the address's
    /// ERC-20 balances as a `Record<contractAddress, decimalString>`. Used by
    /// the EVM coin-finder to know which tokens the address actually holds
    /// (1inch is the source of truth here; Alchemy's `getTokenBalances` was
    /// dropped because it caps at 100 by market cap, so newer tokens fell off
    /// — see #4334).
    case balances(chain: Int, address: String)
    /// `/token/v1.2/{chain}/custom?addresses=...` — bulk metadata lookup keyed
    /// on contract address. Returns `OneInchToken` per address, including the
    /// `providers` array we use to filter to CoinGecko-verified tokens only.
    case customTokens(chain: Int, addresses: [String])

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
        case .balances(let chain, let address):
            return "/1inch/balance/v1.2/\(chain)/balances/\(address)"
        case .customTokens(let chain, _):
            return "/1inch/token/v1.2/\(chain)/custom"
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
        case .customTokens(_, let addresses):
            return .requestParameters([
                "addresses": addresses.joined(separator: ",")
            ], .urlEncoding)
        case .tokens, .balances:
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
