//
//  MayaAssetsDataSource.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

struct MayaAssetsDataSource: AssetSelectionDataSource {
    private let mayaChainAPIService = MayaChainAPIService()

    func fetchAssets() async -> [THORChainAsset] {
        do {
            // Fetch bondable deposit assets from MayaChain
            let assets = try await mayaChainAPIService.getDepositAssets()
            return assets
        } catch {
            print("Error fetching Maya deposit assets: \(error.localizedDescription)")
            return []
        }
    }
}
