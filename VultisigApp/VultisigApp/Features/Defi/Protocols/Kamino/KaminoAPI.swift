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

    static let defaultTimeout: TimeInterval = 60
    static let readTimeout: TimeInterval = 20

    /// Twenty seconds rather than the `TargetType` default of 60 — except for
    /// the position read.
    ///
    /// Measured, this host is the fast half of the feature: `/kvaults` reads
    /// come back in ~100 ms and a build POST in ~0.4 s, with no stall observed
    /// across 150 controlled requests. So 20 s is not a limit any healthy call
    /// approaches — it is there so a Kamino leg cannot become the minute-long
    /// wait the Solana proxy already supplies, on a form that issues several of
    /// them in sequence before the user can do anything.
    ///
    /// ⚠️ The two calls used *only* to leave a position keep the long timeout,
    /// and the reason is asymmetry rather than response size.
    ///
    /// Getting out of a position is the operation whose failure a user cannot
    /// route around inside this app, so it gets the benefit of the doubt. A
    /// `.userPositions` failure leaves `eligibility` unreadable and disables the
    /// withdraw form; a `.withdraw` build failure raises an alert on Continue.
    /// Neither is retried into success by a shorter limit: if the server is slow
    /// enough to blow 20 s it is slow enough to blow the next 20 s too, so
    /// cutting the wait converts "slow" into "cannot withdraw through Vultisig"
    /// rather than into a faster answer.
    ///
    /// Both are also absent from the deposit path, which is the path the short
    /// limit exists to protect — the stall it mitigates was measured on the
    /// Solana proxy, and neither of these calls touches it. So the shorter limit
    /// buys nothing where it was aimed and, if it ever bit, would refuse an exit
    /// the server was merely slow to serve.
    ///
    /// Everything else stays short. `.vaultState` and `.vaultMetrics` are shared
    /// with the deposit form and run several-in-sequence there; `.deposit` is the
    /// way *in*, where a refusal costs an attempt rather than an exit; and a
    /// `.positionPnl` failure is swallowed to `nil` as one display line.
    var timeoutInterval: TimeInterval {
        switch self {
        case .userPositions, .withdraw:
            return Self.defaultTimeout
        case .vaultState, .vaultMetrics, .positionPnl, .deposit:
            return Self.readTimeout
        }
    }

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
