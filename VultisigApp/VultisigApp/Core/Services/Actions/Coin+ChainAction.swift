//
//  Coin+ChainAction.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

extension CoinAction {

    /// Chains that surface the Function (memo) action. Every entry must have a
    /// non-empty `FunctionCallType.getCases(for:)`, and no chain outside this
    /// list may offer cases — otherwise the button either opens an empty
    /// selector or the cases are unreachable. Pinned by tests.
    ///
    /// The THORChain chainnet/stagenet forks are deliberately absent: they had
    /// no selectable functions at all, and the Custom form they fell back to
    /// builds its token list from `.thorChain` / `.mayaChain` only — so the
    /// fork's form came up empty and could never validate.
    static var memoChains: [Chain] = [
        .thorChain, .mayaChain, .dydx, .kujira, .gaiaChain, .osmosis,
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

        return actions.filtered
    }
}

extension Array where Element == CoinAction {
    var filtered: [CoinAction] {
        if !SwapFeatureGate.canSwap() {
            return filter { $0 != .swap }
        } else {
            return self
        }
    }
}
