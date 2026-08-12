//
//  DefiPositionsService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

/// Source of the selectable DeFi position catalog.
///
/// Bond and stake are static, in-app lists and resolve without any network
/// access; only liquidity pools need a live pool list. Callers rely on that
/// split to publish the static sections immediately instead of gating the whole
/// catalog on a network round-trip.
///
/// `Sendable` because the pool fetch is handed to a detached task: the view
/// model captures its provider into the closure it races against a timeout, so
/// every conformer has to be safe to use from another isolation domain.
protocol DefiPositionsProviding: Sendable {
    func bondCoins(for chain: Chain) -> [CoinMeta]
    func stakeCoins(for chain: Chain) -> [CoinMeta]
    /// Whether `lpCoins(for:)` performs a network fetch for this chain. Lets a
    /// caller tell "this chain has no liquidity pools" apart from "the pool list
    /// has not arrived yet", so a chain without LPs never shows a loading state.
    func supportsLiquidityPools(for chain: Chain) -> Bool
    /// Throws on a failed pool fetch so the caller can surface the failure and
    /// offer a retry — an empty return means "this chain genuinely has none".
    func lpCoins(for chain: Chain) async throws -> [CoinMeta]
    /// Curated yield vaults selectable on this chain. Static and offline like
    /// bond and stake: the vaults are an allow-list, and their live state is
    /// hydrated per vault only once the user has enabled one.
    func earnVaults(for chain: Chain) -> [KaminoVaultDescriptor]
}

struct DefiPositionsService: DefiPositionsProviding {
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

    func earnVaults(for chain: Chain) -> [KaminoVaultDescriptor] {
        chain == KaminoVaultRegistry.chain ? KaminoVaultRegistry.allowList : []
    }

    /// Keep in sync with the network-backed branches of `lpCoins(for:)`.
    func supportsLiquidityPools(for chain: Chain) -> Bool {
        switch chain {
        case .thorChain, .mayaChain:
            true
        default:
            false
        }
    }

    func lpCoins(for chain: Chain) async throws -> [CoinMeta] {
        switch chain {
        case .thorChain:
            let pools = try await thorchainService.getPools()
            return pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
        case .mayaChain:
            let pools = try await MayaChainAPIService().getPoolStats(period: SettingsAPRPeriod.current.rawValue)
            return pools.compactMap { THORChainAssetFactory.createCoin(from: $0.asset) }
        default:
            return []
        }
    }
}
