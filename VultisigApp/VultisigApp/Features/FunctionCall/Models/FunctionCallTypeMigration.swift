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
    ///   - coin: the coin currently selected on the legacy screen, which
    ///     supplies the chain the operation runs on.
    ///   - nodeAddress: a node address already typed into the previous
    ///     function's form, carried over as a pre-fill.
    func migratedTransactionType(coin: Coin, nodeAddress: String?) -> FunctionTransactionType? {
        switch self {
        case .leave:
            // LEAVE is a `MsgDeposit` against the chain's own native asset —
            // RUNE on THORChain, CACAO on MayaChain. The legacy screen's
            // `ensureRuneCoin()` pinned RUNE on every chain, MayaChain
            // included, and silently left a non-native selection in place when
            // RUNE was absent.
            return .leave(coin: nativeAsset(for: coin), node: nodeAddress)
        case .withdrawSecuredAsset:
            // A `SECURE-` redemption is signed against the secured asset the
            // user picks inside the form, but the picker itself reads the
            // *native* account's bank balances to find out which secured
            // denoms exist — so that is what the intent names, and what
            // `resolvingCoin` fails closed on. The legacy form answered a
            // RUNE-less vault with "No Secured Assets found", which reads as
            // "you hold nothing" rather than "this vault cannot ask".
            return .withdrawSecuredAsset(coin: nativeAsset(for: coin))
        case .rebond:
            // REBOND is a RUNE `MsgDeposit` on THORChain, and the legacy screen
            // pinned RUNE before opening the form for exactly that reason. Same
            // resolution as LEAVE, same failure mode closed: a vault holding
            // only TCY now lands on the shared "not in vault" error instead of
            // signing a REBOND memo against a token the node never reads.
            return .rebond(coin: nativeAsset(for: coin), node: nodeAddress)
        default:
            // Deliberately an allowlist rather than an exhaustive switch: a
            // type is migrated only once someone has moved it, so the answer
            // for everything else is "still legacy".
            return nil
        }
    }

    /// The chain's own native asset, read from the token store rather than
    /// from the vault so the intent names the asset the operation has to ride
    /// even when the vault does not hold it — `FunctionTransactionScreen`'s
    /// `resolvingCoin` then fails closed on it. Falls back to the selected
    /// coin only when the store knows no native asset for the chain.
    private func nativeAsset(for coin: Coin) -> CoinMeta {
        let nativeAsset = TokensStore.TokenSelectionAssets.first {
            $0.chain == coin.chain && $0.isNativeToken
        }
        return nativeAsset ?? coin.toCoinMeta()
    }
}
