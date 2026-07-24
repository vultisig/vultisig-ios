//
//  DefiPositionsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

struct DefiPositionsService {
    private let thorchainService = THORChainAPIService()

    func bondCoins(for chain: Chain) -> [CoinMeta] {
        switch chain {
        case .thorChain:
            [TokensStore.rune]
        case .mayaChain:
            [TokensStore.cacao]
        default:
            []
        }
    }

    func stakeCoins(for chain: Chain) -> [CoinMeta] {
        switch chain {
        case .thorChain:
            [
                TokensStore.tcy,
                TokensStore.stcy,
                // RUJI's two staking positions are independent and are selected
                // independently: `ruji` is the bonded one (claimable USDC),
                // `sruji` the auto-compounding one (the receipt it mints).
                TokensStore.ruji,
                TokensStore.sruji,
                TokensStore.yrune,
                TokensStore.ytcy,
                // ybRUNE is the auto-compound (`.compound`) position; its card
                // both bonds bRUNE→ybRUNE and unbonds. bRUNE itself is a plain
                // wallet token (no native, non-compound bRUNE staking), so it is
                // intentionally NOT a selectable staking position here.
                TokensStore.ybrune
            ]
        case .mayaChain:
            [
                TokensStore.cacao
            ]
        case .terra:
            [TokensStore.luna]
        case .terraClassic:
            [TokensStore.lunc]
        case .qbtc:
            [TokensStore.qbtc]
        case .ton:
            [TokensStore.ton]
        case .solana:
            // Native SOL has no `TokensStore.sol` static — it is defined inline
            // in `TokenSelectionAssets`. Resolve the native SOL meta from there
            // so the staking position picker has the same coin the vault holds.
            DefiPositionsService.nativeSolanaMeta.map { [$0] } ?? []
        default:
            []
        }
    }

    /// Native SOL `CoinMeta` resolved from `TokenSelectionAssets`. There is no
    /// `TokensStore.sol`; this is the single inline definition of the native
    /// Solana coin, looked up by chain + native flag.
    static let nativeSolanaMeta: CoinMeta? = TokensStore.TokenSelectionAssets
        .first { $0.chain == .solana && $0.isNativeToken }

    func lpCoins(for chain: Chain) async -> [CoinMeta] {
        switch chain {
        case .thorChain:
            let pools = (try? await thorchainService.getPools()) ?? []
            let coins = pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
            return coins
        case .mayaChain:
            let pools = (try? await MayaChainAPIService().getPoolStats(period: SettingsAPRPeriod.current.rawValue)) ?? []
            let coins = pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
            return coins
        default:
            return []
        }
    }
}
