//
//  ThorchainMergeAsset.swift
//  VultisigApp
//
//  One row of the Rujira MERGE picker: a `ThorchainMergeTokens` catalog entry
//  the vault actually holds, paired with the coin that funds the deposit and
//  the wasm contract the deposit is addressed to.
//
//  The list is a static catalog intersected with holdings, not a discovered
//  position — there is nothing to fetch, so the whole thing resolves at view
//  model construction.
//

import Foundation

struct ThorchainMergeAsset: Identifiable {
    /// The catalog entry in its own casing (`thor.kuji`), carrying the denom
    /// and the merge contract that denom deposits into.
    let token: TokenMergeInfo
    /// The vault coin the catalog entry matched. This — not the intent's
    /// anchor coin — is what the transaction is built against, and its balance
    /// is what bounds the amount.
    let coin: Coin
    /// Value-type projection handed to the shared asset picker. Built here, on
    /// the main actor, so the picker's `async` data source never reads the
    /// `@Model` coin off it.
    let pickerAsset: THORChainAsset

    var id: CoinMeta { pickerAsset.asset }

    /// The denom the memo names. The legacy dropdown stored
    /// `token.denom.uppercased()` and the memo was `merge:` + that value, so
    /// the uppercasing is part of the wire format, not a display choice.
    var memoDenom: String { token.denom.uppercased() }

    /// The Rujira merge contract this denom deposits into — one per token, so
    /// it has to follow the selection rather than being fixed per chain.
    var contractAddress: String { token.wasmContractAddress }

    @MainActor
    init(token: TokenMergeInfo, coin: Coin) {
        self.token = token
        self.coin = coin
        self.pickerAsset = THORChainAsset(
            thorchainAsset: token.denom.uppercased(),
            asset: coin.toCoinMeta()
        )
    }
}

extension ThorchainMergeAsset {
    /// The catalog filtered to what the vault holds, **in catalog order**.
    ///
    /// Reproduces the legacy `loadTokens()` match exactly: the denom with its
    /// `thor.` prefix stripped and lowercased, compared against the lowercased
    /// tickers of the vault's coins on `chain`. Ordering matters only in that
    /// it is what the user saw before.
    @MainActor
    static func mergeable(in vault: Vault, chain: Chain) -> [ThorchainMergeAsset] {
        let heldCoins = vault.coins.filter { $0.chain == chain }
        return ThorchainMergeTokens.tokensToMerge.compactMap { token in
            let normalizedDenom = normalized(denom: token.denom)
            guard let coin = heldCoins.first(where: { $0.ticker.lowercased() == normalizedDenom }) else {
                return nil
            }
            return ThorchainMergeAsset(token: token, coin: coin)
        }
    }

    /// The catalog denom `ticker` names, or nil when the ticker is not a
    /// mergeable token. Lets a caller that already knows which token the user
    /// is looking at pre-select it without knowing the catalog's casing.
    static func catalogDenom(forTicker ticker: String) -> String? {
        ThorchainMergeTokens.tokensToMerge
            .first { normalized(denom: $0.denom) == ticker.lowercased() }?
            .denom
    }

    private static func normalized(denom: String) -> String {
        denom.lowercased().replacingOccurrences(of: "thor.", with: "")
    }
}

/// Feeds the shared asset picker from an already-resolved list. The catalog
/// intersection is synchronous and main-actor bound, so it is done once by the
/// view model and this only hands the value types over.
struct ThorchainMergeAssetsDataSource: AssetSelectionDataSource {
    let assets: [THORChainAsset]

    /// Synchronous witness for the `async` requirement: there is nothing to
    /// fetch, the list was resolved when the form was built.
    func fetchAssets() -> [THORChainAsset] {
        assets
    }
}
