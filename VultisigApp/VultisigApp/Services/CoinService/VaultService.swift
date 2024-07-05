//
//  VaultService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 05/07/24.
//

import Foundation

@MainActor
class VaultService {
    
    static func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
        do {
            
            let removedCoins = vault.coins.filter { coin in
                !selection.contains(where: { $0.ticker == coin.ticker && $0.chain == coin.chain})
            }
            let nativeCoins = removedCoins.filter { $0.isNativeToken }
            let allTokens = vault.coins.filter { coin in
                nativeCoins.contains(where: { $0.chain == coin.chain }) && !coin.isNativeToken
            }
            
            let service = CoinService() // this is default to all coins
            try await service.removeCoins(coins: removedCoins, vault: vault)
            try await service.removeCoins(coins: nativeCoins, vault: vault)
            try await service.removeCoins(coins: allTokens, vault: vault)
            
            let filteredSelection = selection.filter{ selection in
                !nativeCoins.contains(where: { selection.ticker == $0.ticker && selection.chain == $0.chain}) &&
                !allTokens.contains(where: { selection.ticker == $0.ticker && selection.chain == $0.chain})
            }
            
            var newCoins: [CoinMeta] = []
            for asset in filteredSelection {
                if !vault.coins.contains(where: { $0.ticker == asset.ticker && $0.chain == asset.chain}) {
                    newCoins.append(asset)
                }
            }
            
            // Each coin must have it's own service so we avoid if, elses.
            let coinServices = Dictionary(grouping: newCoins, by: { CoinServiceFactory.getService(for: $0) })
            for (coinService, coins) in coinServices {
                try await coinService.addToChain(assets: coins, to: vault)
            }
            
        } catch {
            print("fail to save asset,\(error)")
        }
    }
    
}

