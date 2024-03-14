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
        let result = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
        
        switch result {
            case .success(let btc):
                if vault.coins.count == 0 {
                    vault.coins.append(btc)
                } else {
                    coins = vault.coins
                }
                
            case .failure(let error):
                print("error: \(error)")
        }
        categorizeCoins()
    }
    
    private func categorizeCoins() {
        coinsGroupedByChains = [GroupedChain]()
        
        for coin in coins {
            guard coinsGroupedByChains.count>0 else {
                if let element = coins.first {
                    let chain = GroupedChain(
                        name: element.chain.name,
                        address: element.address,
                        count: 1,
                        coins: [coin]
                    )
                    coinsGroupedByChains.append(chain)
                }
                continue
            }
            
            addCoin(coin)
        }
        coinsGroupedByChains.sort { $0.name < $1.name }
    }
    
    private func addCoin(_ coin: Coin) {
        for group in coinsGroupedByChains {
            if group.address == coin.address {
                group.coins.append(coin)
                group.count+=1
                return
            }
        }
        
        let chain = GroupedChain(
            name: coin.chain.name,
            address: coin.address,
            count: 1,
            coins: [coin]
        )
        coinsGroupedByChains.append(chain)
    }
}
