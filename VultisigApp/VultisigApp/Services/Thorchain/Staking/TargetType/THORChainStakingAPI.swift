//
//  THORChainStakingAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/10/2025.
//

import Foundation

/// API endpoints for THORChain ecosystem staking (RUJI and TCY)
enum THORChainStakingAPI: TargetType {
    case getRujiStaking(address: String)
    case getTcyStakedAmount(address: String)
    case getTcyDistributions(limit: Int)
    case getTcyUserDistributions(address: String)  // User-specific distributions from Midgard
    case getBlockHeight
    case getTcyModuleBalance
    case getTcyStakers  // Get all TCY stakers for calculating total staked

    var baseURL: URL {
        switch self {
        case .getRujiStaking:
            return URL(string: "https://api.vultisig.com/ruji/api/graphql")!
        case .getTcyStakedAmount, .getTcyDistributions, .getBlockHeight, .getTcyModuleBalance, .getTcyStakers:
            return URL(string: "https://thornode.ninerealms.com")!
        case .getTcyUserDistributions:
            return URL(string: "https://midgard.ninerealms.com")!
        }
    }

    var path: String {
        switch self {
        case .getRujiStaking:
            return ""  // GraphQL uses POST to base URL
        case .getTcyStakedAmount(let address):
            return "/thorchain/tcy_staker/\(address)"
        case .getTcyDistributions:
            return "/thorchain/tcy_distributions"
        case .getTcyUserDistributions(let address):
            return "/v2/tcy/distribution/\(address)"
        case .getBlockHeight:
            return "/thorchain/lastblock"
        case .getTcyModuleBalance:
            return "/thorchain/balance/module/tcy_stake"
        case .getTcyStakers:
            return "/thorchain/tcy_stakers"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getRujiStaking:
            return .post
        case .getTcyStakedAmount, .getTcyDistributions, .getTcyUserDistributions, .getBlockHeight, .getTcyModuleBalance, .getTcyStakers:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getRujiStaking(let address):
            let query = createGraphQLQuery(address: address)
            let body: [String: Any] = ["query": query]
            return .requestParameters(body, .jsonEncoding)
        case .getTcyStakedAmount, .getBlockHeight, .getTcyModuleBalance, .getTcyUserDistributions, .getTcyStakers:
            return .requestPlain
        case .getTcyDistributions(let limit):
            return .requestParameters(["limit": limit], .urlEncoding)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getRujiStaking:
            return ["Content-Type": "application/json"]
        case .getTcyStakedAmount, .getTcyDistributions, .getBlockHeight, .getTcyModuleBalance, .getTcyStakers:
            return ["X-Client-ID": "vultisig", "Content-Type": "application/json"]
        case .getTcyUserDistributions:
            return ["X-Client-ID": "vultisig"]
        }
    }

    // MARK: - Helper Methods

    /// Creates the GraphQL query for RUJI staking
    private func createGraphQLQuery(address: String) -> String {
        let id = "Account:\(address)".data(using: .utf8)?.base64EncodedString() ?? ""
        return """
        {
          node(id:"\(id)") {
            ... on Account {
              stakingV2 {
                account
                bonded {
                  amount
                  asset {
                    metadata {
                      symbol
                    }
                  }
                }
                pendingRevenue {
                  amount
                  asset {
                    metadata {
                      symbol
                    }
                  }
                }
                pool {
                  summary {
                    apr {
                      value
                    }
                  }
                }
              }
            }
          }
        }
        """
    }
}

// MARK: - Response Models

/// Response model for TCY staker endpoint
struct TcyStakerResponse: Codable {
    let amount: String
}

/// Response model for TCY distribution (global)
struct TcyDistribution: Codable {
    let block: String
    let amount: String
    let timestamp: String?
}

/// Response model for TCY user distributions from Midgard
struct TcyUserDistributionsResponse: Codable {
    let distributions: [TcyUserDistribution]
    let total: String?

    struct TcyUserDistribution: Codable {
        let date: String      // Timestamp
        let amount: String    // RUNE amount in satoshis
    }
}

/// Response model for TCY module balance
struct TcyModuleBalanceResponse: Codable {
    let coins: [ModuleCoin]

    struct ModuleCoin: Codable {
        let denom: String
        let amount: String
    }
}

/// Response model for TCY stakers (all addresses)
struct TcyStakersResponse: Codable {
    let tcy_stakers: [TcyStaker]

    struct TcyStaker: Codable {
        let address: String
        let amount: String
    }
}
