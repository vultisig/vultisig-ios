//
//  CosmosRedelegationCooldownGate.swift
//  VultisigApp
//
//  The cosmos-sdk x/staking module rejects a `MsgBeginRedelegate` if an
//  unexpired redelegation record exists for the same `(src → *)` pair —
//  this is the 21-day cooldown that prevents validator-hopping. The
//  rejection happens post-broadcast, after MPC has already signed.
//
//  This gate evaluates `/cosmos/staking/v1beta1/delegators/{addr}/redelegations`
//  BEFORE the SignDoc is built. If any unfinished redelegation entry
//  references the requested source validator, the redelegate flow is
//  blocked and the UI surfaces the earliest unlock date inline. This is
//  Spec Risk 4: "Don't surprise the user with an MPC burn".
//

import Foundation

enum CosmosRedelegationCooldownState: Equatable {
    /// Source validator has no pending redelegation cooldown — safe to
    /// begin a new redelegation.
    case available
    /// Source validator is under cooldown — surface `unlocksAt` inline.
    case blocked(unlocksAt: Date)
}

enum CosmosRedelegationCooldownGate {
    /// Evaluates whether the source validator is currently under a
    /// redelegation cooldown. Pure function over an LCD-fetched list.
    ///
    /// `now` is injected so the unit tests can pin the boundary
    /// deterministically — production callers pass `Date()`.
    static func evaluate(
        sourceValidator: String,
        redelegations: [CosmosRedelegationEntry],
        now: Date = Date()
    ) -> CosmosRedelegationCooldownState {
        let pending = redelegations
            .filter { $0.srcValidator == sourceValidator && $0.completionTime > now }
            .map(\.completionTime)
            .sorted()

        guard let earliest = pending.first else {
            return .available
        }
        return .blocked(unlocksAt: earliest)
    }
}
