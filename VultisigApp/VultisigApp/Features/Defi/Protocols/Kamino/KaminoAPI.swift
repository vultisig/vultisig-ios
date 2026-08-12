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

    /// Twenty seconds rather than the `TargetType` default of 60.
    ///
    /// Measured, this host is the fast half of the feature: `/kvaults` reads
    /// come back in ~100 ms and a build POST in ~0.4 s, with no stall observed
    /// across 150 controlled requests. So 20 s is not a limit any healthy call
    /// approaches — it is there so a Kamino leg cannot become the minute-long
    /// wait the Solana proxy already supplies, on a form that issues several of
    /// them in sequence before the user can do anything.
    var timeoutInterval: TimeInterval { 20 }

    /// Whether repeating this request is free of consequence, and therefore
    /// whether a timeout may be retried.
    ///
    /// The reads are, by HTTP contract. The two build endpoints are excluded —
    /// and this is the interesting half. `POST /ktx/kvault/{deposit,withdraw}`
    /// is a pure builder: it signs nothing, moves nothing, and every
    /// transaction it returns is validated against the registry and simulated
    /// from scratch before it can reach a signer, so a duplicate build is not
    /// dangerous in the way a duplicate broadcast would be. It is excluded
    /// anyway, for two reasons. A POST carries no idempotence guarantee this
    /// app is entitled to assume about somebody else's service. And it is not
    /// where the problem is: every stall this change exists to absorb was
    /// measured on the Solana RPC proxy, and none on this host — so retrying a
    /// build would assume something undocumented in exchange for nothing
    /// measured.
    var isIdempotentRead: Bool {
        switch self {
        case .vaultState, .vaultMetrics, .userPositions, .positionPnl:
            return true
        case .deposit, .withdraw:
            return false
        }
    }
}
