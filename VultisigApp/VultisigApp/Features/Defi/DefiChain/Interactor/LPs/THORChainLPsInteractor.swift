//
//  THORChainLPsInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import Foundation

struct THORChainLPsInteractor: LPsInteractor {
    private let thorchainAPIService = THORChainAPIService()

    /// Period for LUVI-based APR calculation. Options: "1h", "24h", "7d", "14d", "30d", "90d", "100d", "180d", "365d", "all"
    /// - "7d": Weekly performance, higher volatility
    /// - "30d": Monthly average, balanced view (DEFAULT, matches thorchain.org)
    /// - "100d": Longer-term average, more stable
    /// Default is 30d to match thorchain.org and the API default
    var aprPeriod: String {
        SettingsAPRPeriod.current.rawValue
    }

    func fetchLPPositions(vault: Vault) async -> [LPPosition] {
        guard let runeCoin = vault.runeCoin else { return [] }
        let vaultLPPositions = vault.defiPositions.first { $0.chain == .thorChain }?.lps ?? []

        do {
            // Fetch LP positions from THORChain API using configured period for LUVI-based APR
            let apiPositions = try await thorchainAPIService.getLPPositions(
                address: runeCoin.address,
                userLPs: vaultLPPositions,
                period: aprPeriod
            )

            // Convert THORChainLPPosition to LPPosition
            let positions = try convertToLPPositions(apiPositions, vault: vault)
            await savePositions(positions: positions)
            return positions

        } catch {
            print("Error fetching LP positions: \(error)")
            return []
        }
    }
}

private extension THORChainLPsInteractor {
    func convertToLPPositions(_ apiPositions: [THORChainLPPosition], vault: Vault) throws -> [LPPosition] {
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

    @MainActor
    func savePositions(positions: [LPPosition]) {
        do {
            try DefiPositionsStorageService().upsert(positions)
        } catch {
            print("An error occured while saving LPs positions: \(error)")
        }
    }
}
