//
//  THORChainAssetFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/10/2025.
//

enum THORChainAssetFactory {
    static func createCoin(from asset: String, decimals: Int? = nil) -> CoinMeta? {
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

        let coinMeta = TokensStore.TokenSelectionAssets
            .first { $0.chain == appChain && $0.ticker.lowercased() == symbol.lowercased() }
        if let coinMeta {
            return coinMeta
        } else {
            return CoinMeta(
                chain: appChain,
                ticker: symbol.uppercased(),
                logo: symbol.lowercased(),
                decimals: decimals ?? 8,
                priceProviderId: "",
                contractAddress: contractAddress,
                isNativeToken: contractAddress.isEmpty
            )
        }
    }
}
