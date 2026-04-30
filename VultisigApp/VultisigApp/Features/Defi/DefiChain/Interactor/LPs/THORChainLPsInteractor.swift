//
//  THORChainLPsInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-lps-interactor")

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

    func fetchLPPositions(vault: Vault) async throws -> [LPPositionData] {
        // Snapshot the RUNE coin's address on `MainActor` before the async network call.
        // Reading `Coin` properties off the main actor would violate the SwiftData rule.
        guard let runeAddress = await runeAddress(in: vault) else { return [] }
        let vaultLPPositions = await readVaultLPPositions(in: vault)

        let apiPositions = try await thorchainAPIService.getLPPositions(
            address: runeAddress,
            userLPs: vaultLPPositions,
            period: aprPeriod
        )

        // Persistence is the ViewModel's responsibility — it calls
        // `DefiPositionsStorageService.upsert(lp:for:)` on the returned DTOs. Persisting here
        // too would double-write and double-fire `.defiPositionsDidChange`.
        return convertToLPPositions(apiPositions)
    }
}

private extension THORChainLPsInteractor {
    @MainActor
    func runeAddress(in vault: Vault) -> String? {
        vault.runeCoin?.address
    }

    @MainActor
    func readVaultLPPositions(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.lps ?? []
    }

    func convertToLPPositions(_ apiPositions: [THORChainLPPosition]) -> [LPPositionData] {
        var result: [LPPositionData] = []

        for apiPosition in apiPositions {
            // Parse the pool asset (e.g., "BTC.BTC", "ETH.ETH")
            let components = apiPosition.asset.split(separator: ".")
            guard components.count == 2 else { continue }

            let assetChainName = String(components[0])
            var assetTicker = String(components[1])
            if assetTicker.contains("-") {
                assetTicker = String(assetTicker.split(separator: "-")[0])
            }

            guard let runeCoin = TokensStore.TokenSelectionAssets.first(where: {
                $0.ticker == "RUNE" && $0.isNativeToken
            }) else {
                logger.warning("Could not find RUNE coin")
                continue
            }

            guard let assetCoin = TokensStore.TokenSelectionAssets.first(where: {
                $0.ticker == assetTicker &&
                $0.chain.swapAsset.uppercased() == assetChainName
            }) else {
                logger.warning("Could not find asset coin for: \(assetTicker, privacy: .public) on \(assetChainName, privacy: .public)")
                continue
            }

            // Convert amounts from base units to decimal
            // Note: THORChain uses 8 decimals for RUNE
            let runeAmount = apiPosition.currentRuneAmount / pow(10, runeCoin.decimals)
            let assetAmount = apiPosition.currentAssetAmount / pow(10, runeCoin.decimals)

            result.append(
                LPPositionData(
                    coin1: runeCoin,
                    coin1Amount: runeAmount,
                    coin2: assetCoin,
                    coin2Amount: assetAmount,
                    poolName: apiPosition.asset,
                    poolUnits: apiPosition.poolStats.units,
                    apr: apiPosition.apr // Already in decimal format (e.g., 0.0067 for 0.67%)
                )
            )
        }

        return result
    }
}
