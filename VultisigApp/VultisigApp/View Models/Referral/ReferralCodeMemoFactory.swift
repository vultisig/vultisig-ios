//
//  ReferralCodeMemoFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/08/2025.
//

enum ReferralCodeMemoFactory {
    static func createEdit(referralCode: String, nativeCoin: Coin, preferredAsset: THORChainAsset?, preferredAssetCoin: Coin?) -> String {
        var preferredAssetAddressPart = ":THOR"
        var preferredAssetPart = ""
        if let preferredAsset, let preferredAssetCoin {
            preferredAssetAddressPart = ":\(preferredAsset.asset.chain.swapAsset):\(preferredAssetCoin.address)"
            preferredAssetPart =  preferredAsset.thorchainAsset.isNotEmpty ? ":\(preferredAsset.thorchainAsset)" : .empty
        }

        return "~:\(referralCode.uppercased())\(preferredAssetAddressPart):\(nativeCoin.address)\(preferredAssetPart)"
    }
}
