//
//  MayaChainStakingAPI.swift
//  VultisigApp
//
//  Created by AI Assistant on 23/11/2025.
//

import Foundation

/// API endpoints for MayaChain CACAO staking
enum MayaChainStakingAPI: TargetType {
    case getCacaoPoolMember(address: String)
    case getCacaoPoolHistory(interval: String, count: Int)
    case getPools

    var baseURL: URL {
        switch self {
        case .getCacaoPoolMember, .getCacaoPoolHistory:
            return URL(string: "https://midgard.mayachain.info/v2")!
        case .getPools:
            return URL(string: "https://mayanode.mayachain.info")!
        }
    }

    var path: String {
        switch self {
        case .getCacaoPoolMember(let address):
            return "/cacaopool/\(address)"
        case .getCacaoPoolHistory:
            return "/history/cacaopool"
        case .getPools:
            return "/mayachain/pools"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getCacaoPoolMember, .getCacaoPoolHistory, .getPools:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .getCacaoPoolMember:
            return .requestPlain
        case .getCacaoPoolHistory(let interval, let count):
            return .requestParameters(
                ["interval": interval, "count": count],
                .urlEncoding
            )
        case .getPools:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getCacaoPoolMember, .getCacaoPoolHistory, .getPools:
            return ["X-Client-ID": "vultisig"]
        }
    }
}

// MARK: - Response Models

/// Response model for CACAO pool member
struct MayaCacaoPoolMemberResponse: Codable {
    let cacaoAddress: String
    let cacaoDeposit: String
    let cacaoWithdrawn: String
    let liquidityUnits: String

    enum CodingKeys: String, CodingKey {
        case cacaoAddress = "cacao_address"
        case cacaoDeposit = "cacao_deposit"
        case cacaoWithdrawn = "cacao_withdrawn"
        case liquidityUnits = "liquidity_units"
    }
}

/// Response model for CACAO pool history
struct MayaCacaoPoolHistoryResponse: Codable {
    let intervals: [CacaoPoolInterval]
}

struct CacaoPoolInterval: Codable {
    let startTime: String
    let endTime: String
    let cacaoDepth: String
    let cacaoPoolUnits: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case cacaoDepth = "cacao_depth"
        case cacaoPoolUnits = "cacao_pool_units"
    }
}

/// Response model for Maya pool
struct MayaPoolResponse: Codable {
    let asset: String
    let assetDepth: String
    let cacaoDepth: String
    let liquidityUnits: String
    let bondable: Bool

    enum CodingKeys: String, CodingKey {
        case asset
        case assetDepth = "balance_asset"
        case cacaoDepth = "balance_cacao"
        case liquidityUnits = "lp_units"
        case bondable
    }
}
