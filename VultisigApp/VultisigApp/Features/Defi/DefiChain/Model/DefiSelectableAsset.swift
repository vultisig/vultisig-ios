//
//  DefiSelectableAsset.swift
//  VultisigApp
//

import Foundation

/// One selectable element in the DeFi "Select positions" picker.
///
/// Bond, stake and liquidity-pool positions are wallet coins; a Kamino Earn
/// position is a curated vault, which is not a coin and must never become one.
/// `DefiChainSelectPositionsScreen.onSave` hands its whole selection to
/// `CoinService.addToChain`, so a vault modelled as a `CoinMeta` would be added
/// to `vault.coins` as a real token row — with a market-data lookup and an SPL
/// balance fetch by share mint that always returns zero, because the launch
/// vaults auto-stake their shares into a farm.
///
/// Keeping the two apart at the type level is what makes that structural rather
/// than conventional: the coin buckets stay `[CoinMeta]`, so a vault cannot
/// reach the coin-adding path even by mistake.
enum DefiSelectableAsset: Hashable, Identifiable {
    case coin(CoinMeta)
    case kaminoVault(KaminoVaultDescriptor)

    var id: String {
        switch self {
        case .coin(let meta):
            meta.uniqueId
        case .kaminoVault(let descriptor):
            descriptor.address
        }
    }

    /// The wallet coin behind this element, or `nil` for a Kamino vault. The
    /// only supported way to get a `CoinMeta` out — pattern matching elsewhere
    /// would re-open the "a vault is nearly a coin" seam.
    var coin: CoinMeta? {
        guard case .coin(let meta) = self else { return nil }
        return meta
    }

    /// Free-text the picker's search matches against.
    var searchTerms: [String] {
        switch self {
        case .coin(let meta):
            [meta.ticker, meta.chain.ticker]
        case .kaminoVault(let descriptor):
            [descriptor.fallbackName, descriptor.curator]
        }
    }
}
