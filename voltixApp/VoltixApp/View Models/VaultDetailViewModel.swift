//
//  VaultDetailViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation

class VaultDetailViewModel: ObservableObject {
    @Published var coins = [Coin]()
    
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
    }
}
