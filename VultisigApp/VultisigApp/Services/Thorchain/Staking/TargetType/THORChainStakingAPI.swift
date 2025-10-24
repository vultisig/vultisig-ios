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
    case getBlockHeight
    case getTcyModuleBalance

    var baseURL: URL {
        switch self {
        case .getRujiStaking:
            return URL(string: "https://api.vultisig.com/ruji/api/graphql")!
        case .getTcyStakedAmount, .getTcyDistributions, .getBlockHeight, .getTcyModuleBalance:
            return URL(string: "https://thornode.ninerealms.com")!
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
        case .getBlockHeight:
            return "/thorchain/lastblock"
        case .getTcyModuleBalance:
            return "/thorchain/balance/module/tcy_stake"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getRujiStaking:
            return .post
        case .getTcyStakedAmount, .getTcyDistributions, .getBlockHeight, .getTcyModuleBalance:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getRujiStaking(let address):
            let query = createGraphQLQuery(address: address)
            let body: [String: Any] = ["query": query]
            return .requestParameters(body, .jsonEncoding)
        case .getTcyStakedAmount, .getBlockHeight, .getTcyModuleBalance:
            return .requestPlain
        case .getTcyDistributions(let limit):
            return .requestParameters(["limit": limit], .urlEncoding)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getRujiStaking:
            return ["Content-Type": "application/json"]
        case .getTcyStakedAmount, .getTcyDistributions, .getBlockHeight, .getTcyModuleBalance:
            return ["X-Client-ID": "vultisig", "Content-Type": "application/json"]
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

/// Response model for TCY distribution
struct TcyDistribution: Codable {
    let block: String
    let amount: String
    let timestamp: String?
}

/// Response model for TCY module balance
struct TcyModuleBalanceResponse: Codable {
    let coins: [ModuleCoin]

    struct ModuleCoin: Codable {
        let denom: String
        let amount: String
    }
}
