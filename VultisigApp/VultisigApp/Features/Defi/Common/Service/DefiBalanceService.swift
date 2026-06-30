//
//  DefiBalanceService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

import Foundation

struct DefiBalanceService {
    @MainActor
    func totalBalanceInFiatString(for chains: [Chain], vault: Vault) -> String {
        let chainsBalance = chains
            .filter { CoinAction.defiChains.contains($0) }
            .map { totalBalanceInFiat(for: $0, vault: vault) }
            .reduce(Decimal.zero, +)
        let totalBalance = chainsBalance + yieldTotalBalanceFiatDecimal(for: vault)
        return totalBalance.formatToFiat(includeCurrencySymbol: true)
    }

    func totalBalanceInFiatString(for chain: Chain, vault: Vault) -> String {
        let balanceDecimal = totalBalanceInFiat(for: chain, vault: vault)
        return balanceDecimal.formatToFiat(includeCurrencySymbol: true)
    }

    func totalBalanceInFiat(for chain: Chain, vault: Vault) -> Decimal {
        switch chain {
        case .thorChain:
            thorChainTotalBalanceFiatDecimal(for: vault)
        case .mayaChain:
            mayaChainTotalBalanceFiatDecimal(for: vault)
        case .tron:
            tronTotalBalanceFiatDecimal(for: vault)
        case .ton:
            tonTotalBalanceFiatDecimal(for: vault)
        case .terra, .terraClassic, .qbtc:
            cosmosStakingTotalBalanceFiatDecimal(chain: chain, vault: vault)
        case .solana:
            solanaStakingTotalBalanceFiatDecimal(for: vault)
        default:
            defaultTotalBalanceFiatDecimal(chain: chain, for: vault)
        }
    }

    /// USDC yield-vault positions are stored as `YieldPosition` rows rather than
    /// per-chain coins, so they're summed into the DeFi total separately. Each
    /// `depositedBalance` is in USDC; convert at the USDC coin's fiat rate. Gated
    /// on the per-provider toggle so a disabled provider's stale cache can't
    /// inflate the total.
    @MainActor
    func yieldTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        guard let usdc = vault.coins.first(where: { $0.chain == .ethereum && $0.ticker == "USDC" }) else {
            return .zero
        }
        let storage = YieldPositionStorageService()
        var total = Decimal.zero
        for providerID in DefiYieldProviderID.allCases where vault.isDefiProviderEnabled(providerID) {
            guard let position = storage.position(for: vault, providerID: providerID) else { continue }
            total += usdc.fiat(decimal: position.depositedBalance)
        }
        return total
    }

    /// Number of DeFi positions with a non-zero balance for `chain`. Mirrors
    /// `positionsWithBalanceCount` on Windows (`useDefiChainPortfolios`):
    /// - THORChain / MayaChain: enabled bond + stake + LP positions with amount > 0.
    /// - Tron: `1` if any TRX is staked (frozen + unfreezing), else `0`.
    /// - Terra / TerraClassic: number of native delegations on the vault.
    /// Other DeFi chains fall back to the count of coins with a non-zero DeFi balance.
    func defiPositionCount(for chain: Chain, vault: Vault) -> Int {
        switch chain {
        case .thorChain:
            thorChainPositionCount(for: vault)
        case .mayaChain:
            mayaChainPositionCount(for: vault)
        case .tron:
            tronPositionCount(for: vault)
        case .ton:
            tonPositionCount(for: vault)
        case .terra, .terraClassic, .qbtc:
            cosmosStakingPositionCount(chain: chain, vault: vault)
        case .solana:
            solanaStakingPositionCount(for: vault)
        default:
            defaultPositionCount(chain: chain, for: vault)
        }
    }
}

private extension DefiBalanceService {
    func thorChainTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        guard vault.defiPositions.contains(where: { $0.chain == .thorChain }) else {
            return .zero
        }

        let bondsBalance = getBondsBalance(for: vault, chain: .thorChain)
        let stakedBalances = getStakedBalances(for: vault, chain: .thorChain)
        let lpBalances: Decimal = getLPBalances(for: vault, chain: .thorChain)
        return bondsBalance + stakedBalances + lpBalances
    }

    func mayaChainTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        guard vault.defiPositions.contains(where: { $0.chain == .mayaChain }) else {
            return .zero
        }

        let bondsBalance = getBondsBalance(for: vault, chain: .mayaChain)
        let stakedBalances = getStakedBalances(for: vault, chain: .mayaChain)
        let lpBalances = getLPBalances(for: vault, chain: .mayaChain)
        return bondsBalance + stakedBalances + lpBalances
    }
    /// LUNA / LUNC delegations land on `coin.stakedBalance` via
    /// `BalanceService.fetchStakedBalance(.terra/.terraClassic)`. Gate on the
    /// per-vault opt-in (`defiPositions[chain].staking`) so a vault that hasn't
    /// turned the staking position on doesn't have its delegated balance
    /// silently rolled into the DeFi total — matches the empty-state semantic
    /// in `CosmosStakeDefiView`.
    func cosmosStakingTotalBalanceFiatDecimal(chain: Chain, vault: Vault) -> Decimal {
        guard
            let coin = vault.nativeCoin(for: chain),
            let enabledPositions = vault.defiPositions.first(where: { $0.chain == chain }),
            enabledPositions.staking.contains(coin.toCoinMeta())
        else { return .zero }

        return coin.fiat(decimal: coin.stakedBalanceDecimal)
    }

    func tronTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        // The user's Tron DeFi position is the frozen + unfreezing TRX, not the
        // wallet balance. `BalanceService.fetchStakedBalance` writes the total
        // (in SUN) to `Coin.stakedBalance`; `stakedBalanceDecimal` divides by
        // 10^6 to get TRX. Tron has no per-coin opt-in (all frozen TRX is the
        // position), so we don't gate on `defiPositions`.
        guard let trxCoin = vault.nativeCoin(for: .tron) else { return .zero }
        return trxCoin.fiat(decimal: trxCoin.stakedBalanceDecimal)
    }

    /// The TON DeFi position is the nominator-pool stake surfaced as a
    /// `StakePosition` (active + pending deposit, kept visible through a pending
    /// withdrawal since the funds are still locked in the pool). A TON wallet has
    /// a single always-relevant nominator position, so — like Tron — we don't gate
    /// on the per-coin opt-in (`defiPositions[.ton].staking`); a real stake always
    /// contributes to the DeFi total.
    func tonTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        vault.stakePositions
            .filter { $0.coin.chain == .ton }
            .compactMap { position in
                guard let coin = vault.coin(for: position.coin) else { return nil }
                return coin.fiat(decimal: position.amount)
            }
            .reduce(Decimal.zero, +)
    }

    /// The Solana DeFi position is the delegated SOL across all the vault's
    /// stake accounts. `BalanceService.fetchStakedBalance(.solana)` sums the
    /// delegated lamports of every stake account and writes the total (base
    /// units) to `Coin.stakedBalance`; `stakedBalanceDecimal` divides by 10^9
    /// to get SOL. Solana has no per-coin opt-in (a real stake is always the
    /// vault's SOL DeFi position), so — like Tron — we don't gate on
    /// `defiPositions`. Returning the persisted value keeps the balance stable
    /// through a transient stake-account read failure (which writes nothing).
    func solanaStakingTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        guard let solCoin = vault.nativeCoin(for: .solana) else { return .zero }
        return solCoin.fiat(decimal: solCoin.stakedBalanceDecimal)
    }

    func defaultTotalBalanceFiatDecimal(chain: Chain, for vault: Vault) -> Decimal {
        let coins = vault.coins
            .filter { $0.chain == chain }
            .filter { coin in
                let coinMeta = coin.toCoinMeta()
                return vault.stakePositions.map(\.coin).contains(coinMeta) || vault.bondPositions.map(\.node.coin).contains(coinMeta)
            }

        let coinBalances = coins.map(\.defiBalanceInFiatDecimal)
        return coinBalances.reduce(Decimal(0), { $0 + $1 })
    }

    func getBondsBalance(for vault: Vault, chain: Chain) -> Decimal {
        guard
            let coin = vault.nativeCoin(for: chain),
            let enabledPositions = vault.defiPositions.first(where: { $0.chain == chain }),
            enabledPositions.bonds.contains(coin.toCoinMeta())
        else { return .zero }

        let coinMeta = coin.toCoinMeta()
        return vault.bondPositions
            .filter { $0.node.coin == coinMeta }
            .map(\.amount)
            .map { coin.fiat(decimal: coin.valueWithDecimals(value: $0)) }
            .reduce(Decimal.zero, +)
    }

    func getLPBalances(for vault: Vault, chain: Chain) -> Decimal {
        guard
            let coin = vault.nativeCoin(for: chain),
            let enabledPositions = vault.defiPositions.first(where: { $0.chain == chain })
        else { return .zero }

        return vault.lpPositions
            .filter { $0.coin1.chain == chain && enabledPositions.lps.contains($0.coin2) }
            .map { coin.fiat(decimal: $0.coin1Amount) }
            .reduce(Decimal.zero, +)
    }

    func getStakedBalances(for vault: Vault, chain: Chain) -> Decimal {
        guard
            let enabledPositions = vault.defiPositions.first(where: { $0.chain == chain })
        else { return .zero }

        let filteredStakePositions = vault.stakePositions.filter {
            enabledPositions.staking.contains($0.coin)
        }

        return filteredStakePositions.compactMap { position in
            guard let coin = vault.coin(for: position.coin) else { return nil }
            return coin.fiat(decimal: position.amount)
        }
        .reduce(Decimal.zero, +)
    }

    // MARK: - Position counts

    func thorChainPositionCount(for vault: Vault) -> Int {
        thorMayaPositionCount(for: vault, chain: .thorChain)
    }

    func mayaChainPositionCount(for vault: Vault) -> Int {
        thorMayaPositionCount(for: vault, chain: .mayaChain)
    }

    func thorMayaPositionCount(for vault: Vault, chain: Chain) -> Int {
        guard
            let coin = vault.nativeCoin(for: chain),
            let enabledPositions = vault.defiPositions.first(where: { $0.chain == chain })
        else { return 0 }

        let coinMeta = coin.toCoinMeta()

        let bondCount = enabledPositions.bonds.contains(coinMeta)
            ? vault.bondPositions
                .filter { $0.node.coin == coinMeta && $0.amount > 0 }
                .count
            : 0

        let stakeCount = vault.stakePositions
            .filter { enabledPositions.staking.contains($0.coin) && $0.amount > 0 }
            .count

        let lpCount = vault.lpPositions
            .filter { $0.coin1.chain == chain && enabledPositions.lps.contains($0.coin2) && $0.coin1Amount > 0 }
            .count

        return bondCount + stakeCount + lpCount
    }

    func tronPositionCount(for vault: Vault) -> Int {
        guard let trx = vault.nativeCoin(for: .tron) else { return 0 }
        return trx.stakedBalanceDecimal > 0 ? 1 : 0
    }

    /// Count of TON nominator stake positions with a non-zero amount. Ungated
    /// (no per-coin opt-in) — mirrors Tron, since a real stake is always the
    /// vault's TON position.
    func tonPositionCount(for vault: Vault) -> Int {
        vault.stakePositions
            .filter { $0.coin.chain == .ton && $0.amount > 0 }
            .count
    }

    func cosmosStakingPositionCount(chain: Chain, vault: Vault) -> Int {
        guard
            let coin = vault.nativeCoin(for: chain),
            let enabledPositions = vault.defiPositions.first(where: { $0.chain == chain }),
            enabledPositions.staking.contains(coin.toCoinMeta())
        else { return 0 }

        return vault.stakePositions.filter { $0.coin.chain == chain }.count
    }

    /// `1` when the vault has any delegated SOL, else `0`. The DeFi-main cell
    /// badge counts position *types* with a balance (mirrors Tron's single
    /// frozen-TRX position); the exact per-stake-account breakdown — Solana can
    /// hold N accounts — is rendered as individual rows in `SolanaStakeDefiView`.
    /// Ungated (no per-coin opt-in), matching the balance roll-up above.
    func solanaStakingPositionCount(for vault: Vault) -> Int {
        guard let solCoin = vault.nativeCoin(for: .solana) else { return 0 }
        return solCoin.stakedBalanceDecimal > 0 ? 1 : 0
    }

    func defaultPositionCount(chain: Chain, for vault: Vault) -> Int {
        vault.coins
            .filter { $0.chain == chain && $0.defiBalanceInFiatDecimal > 0 }
            .count
    }
}
