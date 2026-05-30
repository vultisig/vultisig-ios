//
//  MayaChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "mayachain-stake-interactor")

private struct CacaoSnapshot {
    let meta: CoinMeta
    let address: String
    let decimals: Int
}

struct MayaChainStakeInteractor: StakeInteractor {
    private let mayaChainAPIService = MayaChainAPIService()

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        guard let cacao = await cacaoSnapshot(in: vault) else { return [] }

        let enabled = await vaultStakePositions(in: vault)
        guard enabled.contains(where: { $0.ticker == cacao.meta.ticker }) else {
            return []
        }

        let position: MayaCacaoPoolPosition
        do {
            position = try await mayaChainAPIService.getCacaoPoolPosition(address: cacao.address)
        } catch {
            logger.error("Error fetching Maya CACAO staking position: \(error.localizedDescription, privacy: .private)")
            return []
        }

        let stakedAmount = position.stakedAmount / pow(10, cacao.decimals)
        let availableToUnstake = position.availableUnits / pow(10, cacao.decimals)
        let aprData = try? await mayaChainAPIService.getCacaoPoolAPR()

        let unstakeMetadata = await unstakeMetadata(for: position)

        return [
            StakePositionData(
                coin: cacao.meta,
                type: .stake,
                amount: stakedAmount,
                availableToUnstake: availableToUnstake,
                apr: aprData?.apr ?? 0,
                unstakeMetadata: unstakeMetadata
            )
        ]
    }
}

private extension MayaChainStakeInteractor {
    @MainActor
    func cacaoSnapshot(in vault: Vault) -> CacaoSnapshot? {
        guard let coin = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken }) else {
            return nil
        }
        return CacaoSnapshot(meta: coin.toCoinMeta(), address: coin.address, decimals: coin.decimals)
    }

    @MainActor
    func vaultStakePositions(in vault: Vault) -> [CoinMeta] {
        vault.defiPositions.first { $0.chain == .mayaChain }?.staking ?? []
    }

    /// Builds maturity metadata from raw block inputs read live from health (current height) and
    /// mimir (maturity window). On a verification failure the position is surfaced as `.unknown`
    /// rather than dropped — so the unstake CTA is gated with an explanation instead of silently
    /// keeping a stale (possibly still-locked) row.
    func unstakeMetadata(for position: MayaCacaoPoolPosition) async -> UnstakeMetadata {
        guard
            let health = try? await mayaChainAPIService.getHealth(shouldCache: false),
            let mimir = try? await mayaChainAPIService.getMimir()
        else {
            logger.error("Could not verify Maya CACAO maturity (health/mimir unavailable)")
            return .unknown
        }

        return UnstakeMetadata(
            lastDepositHeight: position.lastDepositHeight,
            maturityBlocks: mimir.cacaoPoolDepositMaturityBlocks,
            snapshotHeight: health.lastMayaNode.height,
            snapshotTimestamp: Date().timeIntervalSince1970
        )
    }
}
