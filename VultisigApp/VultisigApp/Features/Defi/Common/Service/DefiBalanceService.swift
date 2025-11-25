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
        return totalBalance.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    func totalBalanceInFiatString(for chain: Chain, vault: Vault) -> String {
        let balanceDecimal = totalBalanceInFiat(for: chain, vault: vault)
        return balanceDecimal.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
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
        guard let runeCoin = vault.runeCoin else { return .zero }
        let coinBalances = defaultTotalBalanceFiatDecimal(chain: .thorChain, for: vault)
        let lpBalances: Decimal = vault.lpPositions
            .filter { $0.coin1.chain == .thorChain }
            .map { runeCoin.fiat(decimal: $0.coin1Amount) }
            .reduce(Decimal.zero, +)
        return coinBalances + lpBalances
    }
    
    func mayaChainTotalBalanceFiatDecimal(for vault: Vault) -> Decimal {
        guard let nativeCoin = vault.nativeCoin(for: .mayaChain) else { return .zero }
        let coinBalances = defaultTotalBalanceFiatDecimal(chain: .mayaChain, for: vault)
        let bondsBalance = vault.bondPositions
            .filter { $0.node.coin.chain == .mayaChain }
            .map { nativeCoin.fiat(decimal: $0.amount) }
            .reduce(Decimal.zero, +)
        let lpBalances: Decimal = vault.lpPositions
            .filter { $0.coin1.chain == .mayaChain }
            .map { nativeCoin.fiat(decimal: $0.coin1Amount) }
            .reduce(Decimal.zero, +)
        return coinBalances + bondsBalance + lpBalances
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
}
