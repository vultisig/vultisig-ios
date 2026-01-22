//
//  DefiBalanceService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

import Foundation

struct DefiBalanceService {
    func totalBalanceInFiatString(for chains: [Chain], vault: Vault) -> String {
        let totalBalance = chains
            .filter { CoinAction.defiChains.contains($0) }
            .map { totalBalanceInFiat(for: $0, vault: vault) }
            .reduce(Decimal.zero, +)
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
        default:
            defaultTotalBalanceFiatDecimal(chain: chain, for: vault)
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
}
