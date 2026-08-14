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
    /// A migrated type must not be the `getDefault(for:)` of a chain that
    /// renders the action *list*: behind the list the dropdown still applies
    /// its default without publishing a change, so the route-out would never
    /// fire and the user would land on a selection with no form.
    ///
    /// A chain offering exactly one operation is exempt, and dYdX is the first
    /// one to use the exemption. Its lone case is necessarily also its default,
    /// and the entry point passes straight through to that operation's
    /// destination without consulting `getDefault` at all — which is precisely
    /// the constraint the action list was built to remove. Pinned by
    /// `FunctionCallMigrationSeamTests.testNoMultiActionChainDefaultsToAMigratedFunction`
    /// and its companion.
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
        case .rebond:
            // REBOND is a RUNE `MsgDeposit` on THORChain, and the legacy screen
            // pinned RUNE before opening the form for exactly that reason. Same
            // resolution as LEAVE, same failure mode closed: a vault holding
            // only TCY now lands on the shared "not in vault" error instead of
            // signing a REBOND memo against a token the node never reads.
            return .rebond(coin: nativeAsset(for: coin), node: nodeAddress)
        case .addThorLP:
            // The entry asset only. Which asset is actually deposited is not
            // known until a pool is picked, and the picker resolves it against
            // the vault's own coins — so the intent names where the user came
            // in, and the form owns the rest. Deliberately NOT pinned to the
            // chain's native asset: an LP add from a token screen is a deposit
            // of that token, and pinning would silently retarget it.
            return .addThorchainLP(coin: coin.toCoinMeta())
        case .merge:
            // MERGE deposits a catalog token into that token's own Rujira
            // contract, so the coin it spends is chosen inside the form from
            // the vault's holdings. What the intent names is the chain anchor
            // — THORChain's native asset, which is also the fee asset — for
            // the same reason `.leave` does: the legacy screen pinned RUNE
            // here (`ensureRuneCoin()`), and a vault that cannot resolve it
            // belongs on the shared "not in vault" error rather than in a form
            // whose deposit it could not pay for.
            //
            // The denom pre-selects the token the user was already looking at.
            // The legacy sub-model tried the same thing in `preSelectToken()`,
            // but the RUNE pin above it meant the match never fired.
            return .merge(
                coin: nativeAsset(for: coin),
                denom: ThorchainMergeAsset.catalogDenom(forTicker: coin.ticker)
            )
        case .unmerge:
            // The merged tokens sit inside the merge contract, not the wallet,
            // and the wasm execute is addressed by contract — so the only coin
            // the form needs the vault to resolve is the one that pays the
            // THORChain fee. Naming RUNE here means a vault that cannot pay
            // lands on the shared "not in vault" error instead of opening a
            // form whose Continue could never produce a signable transaction.
            //
            // The denom pre-selects the merge token matching the coin the user
            // opened Functions from; nil when that coin is RUNE or is not a
            // merge token at all.
            return .unmerge(
                coin: nativeAsset(for: coin),
                denom: MergeTokenCatalog.denom(matching: coin)
            )
        case .withdrawSecuredAsset:
            // A `SECURE-` redemption is signed against the secured asset the
            // user picks inside the form, but the picker itself reads the
            // *native* account's bank balances to find out which secured
            // denoms exist — so that is what the intent names, and what
            // `resolvingCoin` fails closed on. The legacy form answered a
            // RUNE-less vault with "No Secured Assets found", which reads as
            // "you hold nothing" rather than "this vault cannot ask".
            return .withdrawSecuredAsset(coin: nativeAsset(for: coin))
        case .theSwitch:
            // SWITCH is a plain transfer to THORChain's inbound vault for the
            // source chain, and that vault credits the chain's native asset
            // only. The legacy screen used whatever coin happened to be
            // selected, so opening Functions from one of Gaia's IBC tokens
            // (FUZN, KUJI, LVN, …) and picking Switch would have sent that
            // token to the vault, where nothing credits it back. Naming the
            // native asset means a vault that cannot resolve it lands on
            // `FunctionTransactionScreen`'s shared "not in vault" error
            // instead.
            return .theSwitch(coin: nativeAsset(for: coin))
        case .vote:
            // The ballot rides the memo and the deposit is empty, so the only
            // coin the vault has to resolve is the one that pays the dYdX fee —
            // its native asset. A vault that cannot resolve it lands on
            // `FunctionTransactionScreen`'s shared "not in vault" error rather
            // than on a form whose Continue could never be paid for.
            return .dydxVote(coin: nativeAsset(for: coin))
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
