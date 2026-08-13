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
        case .unmerge:
            // The merged tokens sit inside the merge contract, not the wallet,
            // and the wasm execute is addressed by contract — so the only coin
            // the form needs the vault to resolve is the one that pays the
            // THORChain fee. Naming RUNE here means a vault that cannot pay
            // lands on the shared "not in vault" error instead of opening a
            // form whose Continue could never produce a signable transaction.
            let nativeAsset = TokensStore.TokenSelectionAssets.first {
                $0.chain == .thorChain && $0.isNativeToken
            }
            return .unmerge(
                coin: nativeAsset ?? coin.toCoinMeta(),
                // The legacy form pre-selected the merge token matching the
                // coin the user opened Functions from; nil when that coin is
                // RUNE or is not a merge token at all.
                denom: MergeTokenCatalog.denom(matching: coin)
            )
        default:
            // Deliberately an allowlist rather than an exhaustive switch: a
            // type is migrated only once someone has moved it, so the answer
            // for everything else is "still legacy".
            return nil
        }
    }
}
