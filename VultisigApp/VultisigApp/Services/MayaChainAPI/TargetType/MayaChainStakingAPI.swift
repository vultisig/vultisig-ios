//
//  MayaChainStakingAPI.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

/// API endpoints for MayaChain CACAO staking
enum MayaChainStakingAPI: TargetType {
    case getCacaoPoolMember(address: String)
    case getCacaoPoolHistory(interval: String, count: Int)
    case getPools

    var baseURL: URL {
        switch self {
        case .getCacaoPoolHistory:
            return URL(string: "https://midgard.mayachain.info/v2")!
        case .getPools, .getCacaoPoolMember:
            return URL(string: "https://mayanode.mayachain.info")!
        }
    }

    var path: String {
        switch self {
        case .getCacaoPoolMember(let address):
            return "mayachain/cacao_provider/\(address)"
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
    let depositAmount: String
    let withdrawAmount: String
    let units: String
    let value: String
    let pnl: String
    let lastWithdrawHeight: Int64
    let lastDepositHeight: Int64

    enum CodingKeys: String, CodingKey {
        case depositAmount = "deposit_amount"
        case withdrawAmount = "withdraw_amount"
        case units
        case value
        case pnl
        case lastWithdrawHeight = "last_withdraw_height"
        case lastDepositHeight = "last_deposit_height"
    }
}

/// Response model for CACAO pool history
struct MayaCacaoPoolHistoryResponse: Codable {
    let intervals: [CacaoPoolInterval]
    let meta: CacaoPoolMeta
}

struct CacaoPoolInterval: Codable {
    let count: String
    let endTime: String
    let startTime: String
    let units: String

    enum CodingKeys: String, CodingKey {
        case count
        case endTime
        case startTime
        case units
    }
}

struct CacaoPoolMeta: Codable {
    let endCount: String
    let endTime: String
    let endUnits: String
    let startCount: String
    let startTime: String
    let startUnits: String

    enum CodingKeys: String, CodingKey {
        case endCount
        case endTime
        case endUnits
        case startCount
        case startTime
        case startUnits
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
        case liquidityUnits = "LP_units"
        case bondable
    }
}
