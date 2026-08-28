//
//  IBCDestination.swift
//  VultisigApp
//
//  One IBC route out of a chain, as a value: where it lands and which channel
//  it leaves on. The channel travels with the chain rather than being looked up
//  again at submit time, so the route the user picked is the route that gets
//  signed.
//

import Foundation

struct IBCDestination: Equatable, Identifiable, Hashable {
    let chain: Chain
    let sourceChannel: String
    /// The destination chain's native asset, for the picker row. Nil only when
    /// the token store does not know the chain, which would also mean the app
    /// cannot render it — such a route is dropped rather than shown blank.
    let asset: CoinMeta

    var id: String { "\(chain.rawValue)-\(sourceChannel)" }
}

enum IBCDestinationCatalog {

    /// Every chain `coin` can IBC to, in the order `Chain.ibcTo` lists them.
    ///
    /// Empty for a coin with no routes.
    static func destinations(for coin: Coin) -> [IBCDestination] {
        return coin.chain.ibcTo.compactMap { info in
            guard let asset = nativeAsset(for: info.destinationChain) else { return nil }
            return IBCDestination(
                chain: info.destinationChain,
                sourceChannel: info.sourceChannel,
                asset: asset
            )
        }
    }

    private static func nativeAsset(for chain: Chain) -> CoinMeta? {
        TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }
    }
}
