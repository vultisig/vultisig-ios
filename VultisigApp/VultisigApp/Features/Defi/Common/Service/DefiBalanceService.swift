//
//  DefiBalanceService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/11/2025.
//

import Foundation

struct DefiBalanceService {
    func totalBalanceInFiatString(for chain: Chain, vault: Vault) -> String {
        let balanceDecimal = totalBalanceInFiat(for: chain, vault: vault)
        return balanceDecimal.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    func totalBalanceInFiat(for chain: Chain, vault: Vault) -> Decimal {
        switch chain {
        case .thorChain:
            thorChainTotalBalanceFiatDecimal(for: vault)
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
            .map { runeCoin.fiat(decimal: $0.coin1Amount) }
            .reduce(Decimal.zero, +)
        return coinBalances + lpBalances
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
