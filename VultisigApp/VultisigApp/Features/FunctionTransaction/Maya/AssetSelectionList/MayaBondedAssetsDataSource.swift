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

    func fetchAssets() async -> [THORChainAsset] {
        guard !nodeAddress.isEmpty else {
            return []
        }

        do {
            // Fetch bonded LP units for this node and bond address
            guard let bondedPools = try await mayaChainAPIService.getAllBondedLPUnits(
                nodeAddress: nodeAddress,
                bondAddress: bondAddress
            ) else {
                return []
            }

            // Convert bonded pools to THORChainAsset
            let assets = bondedPools.compactMap { (poolAsset, lpUnits) -> THORChainAsset? in
                guard lpUnits > 0,
                      let coin = THORChainAssetFactory.createCoin(from: poolAsset) else {
                    return nil
                }
                return THORChainAsset(thorchainAsset: poolAsset, asset: coin)
            }

            return assets
        } catch {
            print("Error fetching bonded LP positions: \(error.localizedDescription)")
            return []
        }
    }
}
