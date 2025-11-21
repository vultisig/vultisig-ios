//
//  DefiTHORChainLPsViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation
import SwiftData
import BigInt

@MainActor
final class DefiTHORChainLPsViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var lpPositions: [LPPosition] = []
    @Published private(set) var initialLoadingDone: Bool = false
    
    private let logic = DefiTHORChainLPsLogic()
    
    var hasLPPositions: Bool {
        !vaultLPPositions.isEmpty
    }
    
    var vaultLPPositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.lps ?? []
    }

    init(vault: Vault) {
        self.vault = vault
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
        guard hasLPPositions, let runeCoin = vault.runeCoin else {
            lpPositions = []
            initialLoadingDone = true
            return
        }

        lpPositions = vault.lpPositions.filter {
            vaultLPPositions.contains($0.coin2)
        }
        if !lpPositions.isEmpty {
            initialLoadingDone = true
        }

        do {
            let positions = try await logic.fetchAndConvertLPPositions(
                vault: vault,
                vaultLPPositions: vaultLPPositions,
                runeCoin: runeCoin
            )
            
            lpPositions = positions
            await logic.savePositions(positions)
        } catch {
            print("Error fetching LP positions: \(error)")
        }
        
        initialLoadingDone = true
    }
}

struct DefiTHORChainLPsLogic {
    
    private let thorchainAPIService = THORChainAPIService()
    private let positionsStorageService = DefiPositionsStorageService()
    
    /// Period for LUVI-based APR calculation. Options: "1h", "24h", "7d", "14d", "30d", "90d", "100d", "180d", "365d", "all"
    var aprPeriod: String = "100d"
    
    func fetchAndConvertLPPositions(vault: Vault, vaultLPPositions: [CoinMeta], runeCoin: Coin) async throws -> [LPPosition] {
        // Fetch LP positions from THORChain API using configured period for LUVI-based APR
        let apiPositions = try await thorchainAPIService.getLPPositions(
            address: runeCoin.address,
            userLPs: vaultLPPositions,
            period: aprPeriod
        )
        
        // Convert THORChainLPPosition to LPPosition
        return await convertToLPPositions(apiPositions, vault: vault)
    }
    
    @MainActor
    func savePositions(_ positions: [LPPosition]) async {
        do {
            try positionsStorageService.upsert(positions)
        } catch {
            print("An error occured while saving LPs positions: \(error)")
        }
    }
    
    private func convertToLPPositions(_ apiPositions: [THORChainLPPosition], vault: Vault) async -> [LPPosition] {
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
            
            // Find RUNE coin (always coin1)
            guard let runeCoin = TokensStore.TokenSelectionAssets.first(where: {
                $0.ticker == "RUNE" && $0.isNativeToken
            }) else {
                print("Could not find RUNE coin")
                continue
            }
            
            // Find the asset coin (coin2)
            guard let assetCoin = TokensStore.TokenSelectionAssets.first(where: {
                $0.ticker == assetTicker &&
                $0.chain.swapAsset.uppercased() == assetChainName
            }) else {
                print("Could not find asset coin for: \(assetTicker) on \(assetChainName)")
                continue
            }
            
            // Convert amounts from base units to decimal
            // Note: THORChain uses 8 decimals for RUNE
            let runeAmount = apiPosition.currentRuneAmount / pow(10, runeCoin.decimals)
            let assetAmount = apiPosition.currentAssetAmount / pow(10, runeCoin.decimals)
            
            let lpPosition = LPPosition(
                coin1: runeCoin,
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
}
