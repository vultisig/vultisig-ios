//
//  MayaUserLPAssetsDataSource.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/01/2026.
//

import Foundation

/// Data source for Bond screen - fetches user's LP positions that are in bondable pools
struct MayaUserLPAssetsDataSource: AssetSelectionDataSource {
    private let mayaChainAPIService = MayaChainAPIService()
    private let userAddress: String

    init(userAddress: String) {
        self.userAddress = userAddress
    }

    func fetchAssets() async -> [THORChainAsset] {
        do {
            // Fetch bondable pools and user's LP positions in parallel
            async let bondablePoolsTask = mayaChainAPIService.getPools()
            async let memberDetailsTask = mayaChainAPIService.getMemberDetails(address: userAddress)

            let bondablePools = try await bondablePoolsTask
            let memberDetails = try await memberDetailsTask

            // Get set of bondable pool names
            let bondablePoolNames = Set(bondablePools.filter { $0.bondable }.map { $0.asset })

            // Filter user's LP positions to only include bondable pools with liquidity units > 0
            let userBondablePositions = memberDetails.pools.filter { pool in
                let hasUnits = (Int64(pool.liquidityUnits) ?? 0) > 0
                let isBondable = bondablePoolNames.contains(pool.pool)
                return hasUnits && isBondable
            }

            // Convert to THORChainAsset
            let assets = userBondablePositions.compactMap { pool -> THORChainAsset? in
                guard let coin = THORChainAssetFactory.createCoin(from: pool.pool) else {
                    return nil
                }
                return THORChainAsset(thorchainAsset: pool.pool, asset: coin)
            }

            return assets
        } catch {
            print("Error fetching user LP positions: \(error.localizedDescription)")
            return []
        }
    }
}
