//
//  MayaChainLPsInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation

struct MayaChainLPsInteractor: LPsInteractor {
    private let mayaAPIService = MayaChainAPIService()

    var aprPeriod: String {
        SettingsAPRPeriod.current.rawValue
    }

    func fetchLPPositions(vault: Vault) async -> [LPPosition] {
        guard let mayaCoin = vault.nativeCoin(for: .mayaChain) else { return [] }
        let vaultLPPositions = vault.defiPositions.first { $0.chain == .mayaChain }?.lps ?? []
        
        do {
            let apiPositions = try await mayaAPIService.getLPPositions(
                address: mayaCoin.address,
                userLPs: vaultLPPositions,
                period: aprPeriod
            )

            // Convert THORChainLPPosition to LPPosition
            let positions = try await convertToLPPositions(apiPositions, vault: vault)
            await savePositions(positions: positions)
            return positions
            
        } catch {
            print("Error fetching LP positions: \(error)")
            return []
        }
    }
}

private extension MayaChainLPsInteractor {
    func convertToLPPositions(_ apiPositions: [THORChainLPPosition], vault: Vault) async throws -> [LPPosition] {
        var result: [LPPosition] = []
        
        for apiPosition in apiPositions {
            // Parse the pool asset (e.g., "BTC.BTC", "ETH.ETH")
            let components = apiPosition.asset.split(separator: ".")
            guard components.count == 2 else { continue }
            
            let assetChainName = String(components[0])
            var assetTicker = String(components[1])
            if assetTicker.contains("-") {
                assetTicker = String(assetTicker.split(separator: "-")[0])
            }
            
            // Find Cacao coin (always coin1)
            let cacaoCoin = TokensStore.cacao
            
            // Find the asset coin (coin2)
            guard let assetCoin = TokensStore.TokenSelectionAssets.first(where: {
                $0.ticker == assetTicker &&
                $0.chain.swapAsset.uppercased() == assetChainName
            }) else {
                print("Could not find asset coin for: \(assetTicker) on \(assetChainName)")
                continue
            }
            
            // Convert amounts from base units to decimal
            let runeAmount = apiPosition.currentRuneAmount / pow(10, cacaoCoin.decimals)
            let assetAmount = apiPosition.currentAssetAmount / pow(10, cacaoCoin.decimals)
            
            let lpPosition = LPPosition(
                coin1: cacaoCoin,
                coin1Amount: runeAmount,
                coin2: assetCoin,
                coin2Amount: assetAmount,
                poolName: apiPosition.asset,
                poolUnits: apiPosition.poolStats.units,
                apr: apiPosition.apr, // Already in decimal format (e.g., 0.0067 for 0.67%),
                vault: vault
            )
            
            result.append(lpPosition)
        }
        
        return result
    }
    
    @MainActor
    func savePositions(positions: [LPPosition]) async {
        do {
            try DefiPositionsStorageService().upsert(positions)
        } catch {
            print("An error occured while saving LPs positions: \(error)")
        }
    }
}
