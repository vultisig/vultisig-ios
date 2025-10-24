//
//  PreferredAssetFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

enum PreferredAssetFactory {
    static func createCoin(from asset: String, decimals: Int? = nil) -> PreferredAsset? {
        guard let coin = THORChainAssetFactory.createCoin(from: asset, decimals: decimals) else {
            return nil
        }
        
        return PreferredAsset(thorchainAsset: asset, asset: coin)
    }
}
