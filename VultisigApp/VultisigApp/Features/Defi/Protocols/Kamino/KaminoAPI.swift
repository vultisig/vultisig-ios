//
//  KaminoAPI.swift
//  VultisigApp
//

import Foundation

/// Kamino's public REST API. No key, no auth header — the action endpoints build
/// an unsigned Solana transaction from the caller's wallet address alone, which
/// is why every built transaction is validated on-device before it is signed.
enum KaminoAPI: TargetType {

    case vaultState(address: String)
    case vaultMetrics(address: String)
    case userPositions(owner: String)
    case positionPnl(owner: String, vault: String)
    case deposit(request: KaminoActionRequest)
    case withdraw(request: KaminoActionRequest)

    private static let apiBaseURL = URL(staticString: "https://api.kamino.finance")

    var baseURL: URL { Self.apiBaseURL }

    var path: String {
        switch self {
        case .vaultState(let address):
            return "/kvaults/vaults/\(address)"
        case .vaultMetrics(let address):
            return "/kvaults/vaults/\(address)/metrics"
        case .userPositions(let owner):
            return "/kvaults/users/\(owner)/positions"
        case .positionPnl(let owner, let vault):
            return "/kvaults/users/\(owner)/vaults/\(vault)/pnl"
        case .deposit:
            return "/ktx/kvault/deposit"
        case .withdraw:
            return "/ktx/kvault/withdraw"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .vaultState, .vaultMetrics, .userPositions, .positionPnl:
            return .get
        case .deposit, .withdraw:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .vaultState, .vaultMetrics, .userPositions, .positionPnl:
            return .requestPlain
        case .deposit(let request), .withdraw(let request):
            return .requestCodable(request, .jsonEncoding)
        }
    }
}
