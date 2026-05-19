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

    var aprPeriod: String {
        SettingsAPRPeriod.current.rawValue
    }

    func fetchLPPositions(vault: Vault) async -> [LPPositionData] {
        guard let runeAddress = await runeAddress(in: vault) else { return [] }
        let enabled = await readVaultLPPositions(in: vault)
        guard !enabled.isEmpty else { return [] }

        do {
            let apiPositions = try await thorchainAPIService.getLPPositions(
                address: runeAddress,
                userLPs: enabled,
                period: aprPeriod
            )
            return convert(apiPositions)
        } catch {
            logger.error("Failed to fetch THORChain LP positions: \(error.localizedDescription, privacy: .private)")
            return []
        }
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

    func convert(_ apiPositions: [THORChainLPPosition]) -> [LPPositionData] {
        var result: [LPPositionData] = []
        for apiPosition in apiPositions {
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

            // THORChain uses 8 decimals for RUNE
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
                    apr: apiPosition.apr
                )
            )
        }
        return result
    }
}
