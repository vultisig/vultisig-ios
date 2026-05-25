//
//  DiscoveredCosmosDenom.swift
//  VultisigApp
//
//  Value type returned by `CosmosCoinFinder.discoverBankDenoms`. Carries the
//  resolved metadata for one bank denom held at a Terra / TerraClassic
//  address. Mirrors the SDK `DiscoveredToken` shape with the `isHidden` flag
//  preserved — wallets that consume this type decide whether to auto-add the
//  denom to the visible coin list (`isHidden = false`) or only surface it
//  through Manage Tokens (`isHidden = true`).
//

import Foundation

struct DiscoveredCosmosDenom: Equatable {
    let denom: String
    let ticker: String
    let decimals: Int
    let logo: String
    let priceProviderId: String
    let isHidden: Bool
}

extension DiscoveredCosmosDenom {

    /// Project a discovered bank denom into a `CoinMeta` for the given chain.
    /// The denom string maps to `contractAddress` — that's the iOS convention
    /// for non-native Cosmos coins (factory/IBC denoms live in the contract
    /// slot, matching `TokensStore.findTokenMeta` keys).
    ///
    /// `isNativeToken` is always `false`: the chain's native fee denom was
    /// filtered upstream by `CosmosCoinFinder.discoverBankDenoms` so anything
    /// reaching this projection is a discovered side asset, not the native
    /// coin.
    func toCoinMeta(chain: Chain) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: logo,
            decimals: decimals,
            priceProviderId: priceProviderId,
            contractAddress: denom,
            isNativeToken: false
        )
    }
}
