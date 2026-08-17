//
//  MayaChainStakeInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.interactor

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

        let aprData = try? await mayaChainAPIService.getCacaoPoolAPR()
        let unstakeMetadata = await unstakeMetadata(for: position)

        return [
            Self.stakePositionData(
                position: position,
                coin: cacao.meta,
                decimals: cacao.decimals,
                apr: aprData?.apr ?? 0,
                unstakeMetadata: unstakeMetadata
            )
        ]
    }

    /// Projects a fetched CACAO pool position onto the row the DeFi tab renders
    /// and the withdraw sheet is opened from.
    ///
    /// Both figures are the member's CACAO **value**, and deliberately the same
    /// figure. The position also carries the member's pool *units*, which are a
    /// different scale entirely — value = units × the pool's CACAO-per-unit, a
    /// rate that only rises as the pool earns — so feeding one to the card and
    /// the other to the sheet showed the user a quantity they never held.
    ///
    /// `availableToUnstake` is not merely a label. It is the ceiling the sheet
    /// renders, validates against, and derives the signed fraction from: a CACAO
    /// withdrawal carries no coin amount at all, only a basis-point share of the
    /// position (`POOL-:<bps>`). A share picked off the slider is unaffected by
    /// what the ceiling is denominated in, but a *typed* amount is read as a
    /// fraction of it — so the ceiling has to be denominated in what the user is
    /// typing, or the fraction asks for the wrong money.
    ///
    /// Pure, and separated from the fetch above, so the projection is exercised
    /// without a network hop.
    static func stakePositionData(
        position: MayaCacaoPoolPosition,
        coin: CoinMeta,
        decimals: Int,
        apr: Double,
        unstakeMetadata: UnstakeMetadata
    ) -> StakePositionData {
        let cacaoValue = position.stakedAmount / pow(10, decimals)

        return StakePositionData(
            coin: coin,
            type: .stake,
            amount: cacaoValue,
            availableToUnstake: cacaoValue,
            apr: apr,
            unstakeMetadata: unstakeMetadata
        )
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
