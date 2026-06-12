//
//  CosmosRedelegationCooldownGate.swift
//  VultisigApp
//
//  The cosmos-sdk x/staking module rejects a `MsgBeginRedelegate` via
//  `HasReceivingRedelegation(delAddr, valSrcAddr)` — i.e. when the proposed
//  SOURCE validator is the DESTINATION of an existing unfinished
//  redelegation by the same delegator. After `A -> B`, a new `B -> C` is
//  rejected with `ErrTransitiveRedelegation`. The 21-day cooldown is
//  enforced post-broadcast, after MPC has already signed.
//
//  This gate evaluates `/cosmos/staking/v1beta1/delegators/{addr}/redelegations`
//  BEFORE the SignDoc is built. The filter looks at `dstValidator ==
//  sourceValidator` — i.e. the proposed source was recently a destination —
//  to mirror the chain's `HasReceivingRedelegation` rule. Spec Risk 4:
//  "Don't surprise the user with an MPC burn".
//
//  Original port (PR #4432) had the filter inverted (`srcValidator ==
//  sourceValidator`). vultisig-android caught and fixed it in commit
//  `3729dc6dd` of its #4687 PR; this is the iOS-side cross-platform patch.
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
            .filter { $0.dstValidator == sourceValidator && $0.completionTime > now }
            .map(\.completionTime)
            .sorted()

        guard let earliest = pending.first else {
            return .available
        }
        return .blocked(unlocksAt: earliest)
    }
}
