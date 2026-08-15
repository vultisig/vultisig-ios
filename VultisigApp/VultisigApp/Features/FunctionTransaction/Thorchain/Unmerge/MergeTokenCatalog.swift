//
//  MergeTokenCatalog.swift
//  VultisigApp
//
//  The RUJI merge tokens the app can actually unmerge, expressed as the shared
//  `THORChainAsset` the asset-picker sheet already renders.
//
//  Membership is `ThorchainMergeTokens.tokensToMerge` intersected with the
//  token store. A denom outside that list has no `wasmContractAddress`, and the
//  wasm execute is addressed by contract — the legacy form offered such denoms
//  (it appended every on-chain merge account it found) and built a transaction
//  with an empty contract address, which can only fail at signing. Narrowing
//  the picker closes that by construction, so the builder's contract address is
//  non-optional rather than guarded at submit time.
//

import Foundation

enum MergeTokenCatalog {
    /// Every merge token with both a known merge contract and a known asset.
    static var tokens: [THORChainAsset] {
        ThorchainMergeTokens.tokensToMerge.compactMap { token in
            guard let asset = asset(for: token.denom) else { return nil }
            return THORChainAsset(thorchainAsset: token.denom, asset: asset)
        }
    }

    static func contractAddress(for denom: String) -> String? {
        ThorchainMergeTokens.tokensToMerge
            .first { $0.denom.caseInsensitiveCompare(denom) == .orderedSame }?
            .wasmContractAddress
    }

    /// The merge denom a coin selected elsewhere in the app stands for, or nil
    /// when it is not a merge token. Mirrors the legacy form's `preSelectToken`,
    /// which matched the selected coin's ticker against `thor.<ticker>` and only
    /// for a non-native coin — RUNE is never a merge token.
    static func denom(matching coin: Coin) -> String? {
        guard !coin.isNativeToken else { return nil }
        let candidate = "thor.\(coin.ticker.lowercased())"
        return ThorchainMergeTokens.tokensToMerge
            .first { $0.denom.caseInsensitiveCompare(candidate) == .orderedSame }?
            .denom
    }

    private static func asset(for denom: String) -> CoinMeta? {
        TokensStore.TokenSelectionAssets.first {
            $0.chain == .thorChain && $0.contractAddress.caseInsensitiveCompare(denom) == .orderedSame
        }
    }
}

/// Feeds `AssetSelectionListScreen`. The catalog is static, so there is nothing
/// to await — the data source exists only to satisfy the shared picker's
/// protocol, which the Maya flows implement over the network.
struct MergeTokenDataSource: AssetSelectionDataSource {
    // swiftlint:disable:next async_without_await
    func fetchAssets() async -> [THORChainAsset] {
        MergeTokenCatalog.tokens
    }
}
