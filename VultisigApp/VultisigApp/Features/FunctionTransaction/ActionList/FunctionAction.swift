//
//  FunctionAction.swift
//  VultisigApp
//
//  The operations the Functions entry point offers on a chain, and the intent
//  each one opens.
//
//  Was `FunctionAction` plus `FunctionActionMigration`, the enum that drove
//  a dropdown over a screen of per-operation forms and the temporary table that
//  said which of those had moved. Both are gone: every operation is a
//  `FunctionTransactionType` now, so the mapping is total and the two files had
//  nothing left to say separately.
//
//  What survives is the part that was never about the legacy screen — which
//  operations a chain offers, in what order, and what each is called — read by
//  `FunctionActionCatalog` to build the action list.
//

import SwiftUI

enum FunctionAction: String, CaseIterable, Identifiable {
    case
         rebond,
         leave,
         custom,
         vote,
         cosmosIBC,
         addThorLP,
         withdrawSecuredAsset

    var id: String { self.rawValue }

    func display() -> String {
        switch self {
        case .rebond:
            return "Rebond".localized
        case .leave:
            return "Leave".localized
        case .custom:
            return "Custom".localized
        case .vote:
            return "Vote".localized
        case .cosmosIBC:
            return "IBC Transfer".localized
        case .addThorLP:
            return "Add THORChain LP".localized
        case .withdrawSecuredAsset:
            return "withdrawSecuredAsset".localized
        }
    }

    /// Every operation `coin.chain` offers, in the order the chain lists them.
    ///
    /// The single source of truth for what the Functions entry point shows.
    /// `CoinAction.memoChains` decides whether the entry point appears at all,
    /// and the two have to agree in both directions — pinned by
    /// `FunctionActionReachabilityTests`.
    static func offered(on coin: Coin) -> [FunctionAction] {
        switch coin.chain {
        case .thorChain:
            return [
                .rebond,
                .leave,
                .custom,
                .withdrawSecuredAsset
            ]

        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple:
            return [.addThorLP]
        case .mayaChain:
            return [.leave,
                    .custom]
        case .dydx:
            return [.vote]
        case .gaiaChain, .kujira, .osmosis:
            return [.cosmosIBC]

        case .thorChainChainnet, .thorChainStagenet:
            // The test networks offer the entry button but had no case list,
            // so the selector opened empty over whatever form the default
            // happened to build. Custom is the operation they support — the
            // same `MsgDeposit` mainnet takes — so naming it here makes the
            // button lead somewhere. The form's asset predicate has to know
            // these chains too, or the form it opens could never be submitted.
            return [.custom]

        default:
            return []
        }
    }

    /// The transaction this operation opens.
    ///
    /// Total: every operation has its own screen, so there is no "still on the
    /// legacy form" answer left to give. Several arms read `coin` — `.leave`
    /// and `.rebond` resolve the chain's native asset rather than whatever the
    /// user was looking at, `.custom` and `.cosmosIBC` deliberately carry the
    /// selected one — so this is asked per coin, not once per operation.
    ///
    /// - Parameters:
    ///   - coin: the coin the entry point was opened on, which supplies both
    ///     the chain and, for the operations that spend what you are holding,
    ///     the asset.
    ///   - nodeAddress: a node address a caller already knows, carried into the
    ///     form as a pre-fill. The action list passes nil: it is entered cold.
    func transactionType(coin: Coin, nodeAddress: String? = nil) -> FunctionTransactionType {
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
        case .withdrawSecuredAsset:
            // A `SECURE-` redemption is signed against the secured asset the
            // user picks inside the form, but the picker itself reads the
            // *native* account's bank balances to find out which secured
            // denoms exist — so that is what the intent names, and what
            // `resolvingCoin` fails closed on. The legacy form answered a
            // RUNE-less vault with "No Secured Assets found", which reads as
            // "you hold nothing" rather than "this vault cannot ask".
            return .withdrawSecuredAsset(coin: nativeAsset(for: coin))
        case .vote:
            // The ballot rides the memo and the deposit is empty, so the only
            // coin the vault has to resolve is the one that pays the dYdX fee —
            // its native asset. A vault that cannot resolve it lands on
            // `FunctionTransactionScreen`'s shared "not in vault" error rather
            // than on a form whose Continue could never be paid for.
            //
            // dYdX by name, not `coin.chain`. The operation is only offered
            // there, so the two agree today — but the memo is a dYdX governance
            // vote whatever the entry coin was, and a chain-relative answer
            // would quietly follow a caller that opened it from somewhere else.
            return .dydxVote(coin: nativeAsset(on: .dydx, fallback: coin))
        case .cosmosIBC:
            // The asset leaving the source chain, as selected — an IBC transfer
            // moves whatever the user is holding, so this is deliberately NOT
            // pinned to the chain's native asset the way LEAVE and SWITCH are.
            // The destination side of the hop is an address, not a holding, so
            // it is nothing the vault has to resolve.
            return .ibcTransfer(coin: coin.toCoinMeta(), destinationChain: nil)
        case .custom:
            // The coin the user opened on. The form can swap it for another of
            // the vault's coins on the same chain, and every one of those is
            // already held, so nothing beyond the entry coin needs resolving.
            return .customMemo(coin: coin.toCoinMeta())
        }
    }

    /// The chain's own native asset, read from the token store rather than
    /// from the vault so the intent names the asset the operation has to ride
    /// even when the vault does not hold it — `FunctionTransactionScreen`'s
    /// `resolvingCoin` then fails closed on it. Falls back to the selected
    /// coin only when the store knows no native asset for the chain.
    private func nativeAsset(for coin: Coin) -> CoinMeta {
        nativeAsset(on: coin.chain, fallback: coin)
    }

    /// The native asset of a named chain, for the operations that run on one
    /// chain whatever coin the user entered on.
    private func nativeAsset(on chain: Chain, fallback coin: Coin) -> CoinMeta {
        let nativeAsset = TokensStore.TokenSelectionAssets.first {
            $0.chain == chain && $0.isNativeToken
        }
        return nativeAsset ?? coin.toCoinMeta()
    }
}
