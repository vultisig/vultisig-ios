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
            // RUNE on THORChain, CACAO on MayaChain. Resolving it from the
            // token store rather than from the vault is deliberate: a vault
            // that does not hold the native coin then lands on
            // `FunctionTransactionScreen`'s shared "not in vault" error
            // instead of signing the memo against whichever token happened to
            // be selected. The legacy screen's `ensureRuneCoin()` pinned RUNE
            // on every chain, MayaChain included, and silently left a
            // non-native selection in place when RUNE was absent.
            let nativeAsset = TokensStore.TokenSelectionAssets.first {
                $0.chain == coin.chain && $0.isNativeToken
            }
            return .leave(coin: nativeAsset ?? coin.toCoinMeta(), node: nodeAddress)
        case .merge:
            // MERGE deposits a catalog token into that token's own Rujira
            // contract, so the coin it spends is chosen inside the form from
            // the vault's holdings. What the intent names is the chain anchor
            // — THORChain's native asset, which is also the fee asset — for
            // the same reason `.leave` does: the legacy screen pinned RUNE
            // here (`ensureRuneCoin()`), and a vault that cannot resolve it
            // belongs on the shared "not in vault" error rather than in a form
            // whose deposit it could not pay for.
            let nativeAsset = TokensStore.TokenSelectionAssets.first {
                $0.chain == coin.chain && $0.isNativeToken
            }
            // Pre-select the token the user was already looking at. The legacy
            // sub-model tried the same thing in `preSelectToken()`, but the
            // RUNE pin above it meant the match never fired.
            return .merge(
                coin: nativeAsset ?? coin.toCoinMeta(),
                denom: ThorchainMergeAsset.catalogDenom(forTicker: coin.ticker)
            )
        default:
            // Deliberately an allowlist rather than an exhaustive switch: a
            // type is migrated only once someone has moved it, so the answer
            // for everything else is "still legacy".
            return nil
        }
    }
}
