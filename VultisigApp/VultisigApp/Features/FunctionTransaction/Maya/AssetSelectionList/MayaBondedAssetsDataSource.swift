//
//  MayaBondedAssetsDataSource.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/01/2026.
//

import Foundation
import Combine

/// Data source for Unbond screen - fetches user's bonded LP positions on a specific node
class MayaBondedAssetsDataSource: AssetSelectionDataSource {
    private let mayaChainAPIService = MayaChainAPIService()
    private let bondAddress: String

    @Published var nodeAddress: String = ""

    init(bondAddress: String) {
        self.bondAddress = bondAddress
    }

    func fetchAssets() async throws -> [THORChainAsset] {
        guard !nodeAddress.isEmpty else {
            return []
        }

        // Fetch bonded LP units for this node and bond address. A nil result
        // means the bond address is not a provider on this node — an answer,
        // not a failure.
        guard let bondedPools = try await mayaChainAPIService.getAllBondedLPUnits(
            nodeAddress: nodeAddress,
            bondAddress: bondAddress
        ) else {
            return []
        }

        // Convert bonded pools to THORChainAsset
        return bondedPools.compactMap { (poolAsset, lpUnits) -> THORChainAsset? in
            guard lpUnits > 0,
                  let coin = THORChainAssetFactory.createCoin(from: poolAsset) else {
                return nil
            }
            return THORChainAsset(thorchainAsset: poolAsset, asset: coin)
        }
    }
}
