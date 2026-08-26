//
//  Coin+ChainAction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

extension CoinAction {

    /// Chains that surface the Function (memo) action. Every entry must have a
    /// non-empty `FunctionAction.offered(on:)`, and no chain outside this
    /// list may offer operations — otherwise the button either opens an empty
    /// action list or the operations are unreachable. Pinned by tests.
    ///
    /// The THORChain chainnet/stagenet forks are listed. They were the
    /// motivating case for dropping a chain from this list — they had no case
    /// list, so the button opened an empty selector over a Custom form whose
    /// token list knew only `.thorChain` / `.mayaChain` and could never
    /// validate. Both halves were closed instead of the button removed: the
    /// forks now offer the raw-memo operation, and that operation's asset
    /// predicate lists them alongside mainnet, because they run the same
    /// `MsgDeposit`.
    static var memoChains: [Chain] = [
        .thorChain, .thorChainChainnet, .thorChainStagenet, .mayaChain, .dydx, .gaiaChain, .osmosis,
        // THORChain LP supported chains
        .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .ethereum, .avalanche, .bscChain, .base, .ripple
    ]

    static var defiChains: [Chain] = [
        .thorChain,
        .mayaChain,
        .tron,
        .terra,
        .terraClassic,
        .qbtc,
        .ton,
        .solana
    ]

}

extension Chain {
    var defaultActions: [CoinAction] {

        guard isSupported else { return [] }

        var actions: [CoinAction] = []

        if self.isSwapAvailable {
            actions.append(.swap)
        }
        actions.append(.send) // always include send

        if self.isBuyAvailable {
            actions.append(.buy)
        }
        let enableSell = UserDefaults.standard.bool(forKey: "SellEnabled")
        if enableSell {
            actions.append(.sell)
        }

        if CoinAction.memoChains.contains(self) {
            actions.append(.memo)
        }

        actions.append(.receive)

        return actions
    }
}
