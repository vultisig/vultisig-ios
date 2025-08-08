//
//  PreferredAssetFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

enum PreferredAssetFactory {
    static func createCoin(from asset: String, decimals: Int? = nil) -> PreferredAsset? {
        let splitAsset = asset.split(separator: ".")
        
        let chain = String(splitAsset[safe: 0] ?? "")
        let assetPart = splitAsset[safe: 1]
        var symbol = chain
        var contractAddress = ""
        
        if let assetPart {
            if assetPart.contains("-") {
                let split = assetPart.split(separator: "-")
                symbol = String(split[0])
                contractAddress = String(split[1])
            } else {
                symbol = String(assetPart)
                contractAddress = chain == "THOR" ? assetPart.lowercased() : ""
            }
        }
        
        let appChain = Chain.allCases.first { $0.swapAsset == chain }
        guard let appChain else { return nil }
        
        let priceProviderId = TokensStore.TokenSelectionAssets
            .first { $0.chain == appChain && $0.ticker.localizedCaseInsensitiveContains(symbol) }?
            .priceProviderId ?? ""
        let coin = CoinMeta(
            chain: appChain,
            ticker: symbol.uppercased(),
            logo: symbol.lowercased(),
            decimals: decimals ?? 6,
            priceProviderId: priceProviderId,
            contractAddress: contractAddress,
            isNativeToken: contractAddress.isEmpty
        )
        
        return PreferredAsset(thorchainAsset: asset, asset: coin)
    }
}
