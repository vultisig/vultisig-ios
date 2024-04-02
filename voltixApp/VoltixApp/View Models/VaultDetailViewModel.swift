//
//  VaultDetailViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation

class VaultDetailViewModel: ObservableObject {
    @Published var coins = [Coin]()
    @Published var coinsGroupedByChains = [GroupedChain]()
    
    func fetchCoins(for vault: Vault) {
        // add bitcoin when the vault doesn't have any coins in it
        if vault.coins.count == 0 {
            let result = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
            
            switch result {
            case .success(let btc):
                vault.coins.append(btc)
            case .failure(let error):
                print("error: \(error)")
            }
        }
        coins = vault.coins
        categorizeCoins()
    }
    
    private func categorizeCoins() {
        coinsGroupedByChains = [GroupedChain]()
        
        for coin in coins {
            addCoin(coin)
        }
        coinsGroupedByChains.sort { $0.name < $1.name }
    }
    
    private func addCoin(_ coin: Coin) {
        for group in coinsGroupedByChains {
            if group.address == coin.address && group.name == coin.chain.name {
                group.coins.append(coin)
                group.count+=1
                if coin.isNativeToken {
                    group.logo = coin.logo
                }
                return
            }
        }
        
        let chain = GroupedChain(
            name: coin.chain.name,
            address: coin.address,
            logo: coin.logo,
            count: 1,
            coins: [coin]
        )
        coinsGroupedByChains.append(chain)
    }
}
