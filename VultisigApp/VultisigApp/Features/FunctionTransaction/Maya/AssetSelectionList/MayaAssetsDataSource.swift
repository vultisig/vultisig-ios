//
//  MayaAssetsDataSource.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

struct MayaAssetsDataSource: AssetSelectionDataSource {
    private let mayaChainAPIService = MayaChainAPIService()

    func fetchAssets() async throws -> [THORChainAsset] {
        // Fetch bondable deposit assets from MayaChain
        try await mayaChainAPIService.getDepositAssets()
    }
}
