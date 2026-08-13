//
//  FunctionCallTypeMigration.swift
//  VultisigApp
//
//  The one place that says which legacy function types have already moved to
//  `Features/FunctionTransaction/`, and what intent each of them produces.
//
//  Why this exists: the legacy details screen is still the only entry point
//  for these operations, but a migrated operation no longer has a legacy
//  sub-model for that screen to build. Rather than special-casing each
//  migration inside the screen, the screen asks this mapping once — a non-nil
//  answer means "route out to `FunctionTransactionScreen`", nil means "build
//  the legacy sub-model as before".
//
//  Migrating the next operation is one entry here, plus its case name on the
//  screen's already-migrated arm. Nothing else in the legacy screen changes.
//
//  This whole file is scaffolding for the interim: the action-list screen
//  takes over producing these intents, and the last migration deletes the
//  legacy shell along with this mapping.
//

import Foundation

extension FunctionCallType {
    /// The `FunctionTransactionType` this function selection routes to, or
    /// `nil` when the operation still lives on the legacy screen.
    ///
    /// A migrated type must never be a chain's `getDefault(for:)`: the default
    /// is applied without publishing a change, so the route-out would never
    /// fire and the user would land on a selection with no form.
    ///
    /// - Parameters:
    ///   - coin: the coin currently selected on the legacy screen. The vault
    ///     already holds it, so `FunctionTransactionScreen` resolves it
    ///     without a coin-addition step.
    ///   - vault: resolves the coin an operation is pinned to when it is not
    ///     the selected one.
    ///   - nodeAddress: a node address already typed into the previous
    ///     function's form, carried over as a pre-fill.
    func migratedTransactionType(coin: Coin, vault: Vault, nodeAddress: String?) -> FunctionTransactionType? {
        switch self {
        case .leave:
            // LEAVE is a `MsgDeposit` against the chain's native asset — the
            // legacy screen pinned RUNE here for the same reason, though it
            // pinned RUNE on MayaChain too. Resolving the chain's own native
            // coin keeps THORChain's behaviour and fixes Maya's. Falling back
            // to the selected coin preserves the legacy no-op when the vault
            // holds no native coin for the chain.
            let leaveCoin = vault.nativeCoin(for: coin.chain) ?? coin
            return .leave(coin: leaveCoin.toCoinMeta(), node: nodeAddress)
        default:
            // Deliberately an allowlist rather than an exhaustive switch: a
            // type is migrated only once someone has moved it, so the answer
            // for everything else is "still legacy".
            return nil
        }
    }
}
