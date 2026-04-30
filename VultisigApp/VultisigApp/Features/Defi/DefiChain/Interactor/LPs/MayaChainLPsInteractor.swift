//
//  MayaChainLPsInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/11/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "mayachain-lps-interactor")

struct MayaChainLPsInteractor: LPsInteractor {
    private let mayaAPIService = MayaChainAPIService()

    var aprPeriod: String {
        SettingsAPRPeriod.current.rawValue
    }

    func fetchLPPositions(vault: Vault) async throws -> [LPPositionData] {
        // Snapshot CACAO's address + decimals on `MainActor` before the async network call.
        guard let cacao = await cacaoSnapshot(in: vault) else { return [] }
        let vaultLPPositions = await readVaultLPPositions(in: vault)

        let apiPositions = try await mayaAPIService.getLPPositions(
            address: cacao.address,
            userLPs: vaultLPPositions,
            period: aprPeriod
        )

        // Persistence is the ViewModel's responsibility — see THORChainLPsInteractor.
        return convertToLPPositions(apiPositions, cacaoDecimals: cacao.decimals)
    }
}

private struct CacaoLPSnapshot {
    let address: String
    let decimals: Int
}

private extension MayaChainLPsInteractor {
    @MainActor
    func cacaoSnapshot(in vault: Vault) -> CacaoLPSnapshot? {
        guard let coin = vault.nativeCoin(for: .mayaChain) else { return nil }
        return CacaoLPSnapshot(address: coin.address, decimals: coin.decimals)
    }

    @MainActor
    func readVaultLPPositions(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .mayaChain }?.lps ?? []
    }

    func convertToLPPositions(_ apiPositions: [THORChainLPPosition], cacaoDecimals: Int) -> [LPPositionData] {
        var result: [LPPositionData] = []
        let cacaoCoin = TokensStore.cacao

        for apiPosition in apiPositions {
            // Parse the pool asset (e.g., "BTC.BTC", "ETH.ETH")
            let components = apiPosition.asset.split(separator: ".")
            guard components.count == 2 else { continue }

            let assetChainName = String(components[0])
            var assetTicker = String(components[1])
            if assetTicker.contains("-") {
                assetTicker = String(assetTicker.split(separator: "-")[0])
            }

            guard let assetCoin = TokensStore.TokenSelectionAssets.first(where: {
                $0.ticker == assetTicker &&
                $0.chain.swapAsset.uppercased() == assetChainName
            }) else {
                logger.warning("Could not find asset coin for: \(assetTicker, privacy: .public) on \(assetChainName, privacy: .public)")
                continue
            }

            let cacaoAmount = apiPosition.currentRuneAmount / pow(10, cacaoDecimals)
            let assetAmount = apiPosition.currentAssetAmount / pow(10, cacaoDecimals)

            result.append(
                LPPositionData(
                    coin1: cacaoCoin,
                    coin1Amount: cacaoAmount,
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
