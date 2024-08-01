//
//  VaultDefaultCoinService.swift
//  VultisigApp
//
//  Created by Johnny Luo on 3/6/2024.
//

import Foundation
import SwiftData


class VaultDefaultCoinService {
    let context: ModelContext
    private let semaphore = DispatchSemaphore(value: 1)
    let baseDefaultChains = [Chain.bitcoin, Chain.ethereum, Chain.thorChain, Chain.solana,Chain.bscChain]
    
    init(context:ModelContext){
        self.context = context
    }
    
    func setDefaultCoinsOnce(vault: Vault, defaultChains: [CoinMeta]) {
        semaphore.wait()
        defer {
            semaphore.signal()
        }
        setDefaultCoins(for: vault, defaultChains: defaultChains)
    }
    
    func setDefaultCoins(for vault: Vault, defaultChains: [CoinMeta]) {
        // Add default coins when the vault doesn't have any coins in it
        print("set default chains to vault")
        if vault.coins.count == 0 {
            let chains: [CoinMeta]
            
            if defaultChains.count==0 {
                chains = TokensStore.TokenSelectionAssets
                    .filter { asset in baseDefaultChains.contains(where: { $0 == asset.chain }) }
            } else {
                chains = defaultChains
            }
            
            let coins = chains
                .compactMap { try? CoinFactory.create(
                    asset: $0,
                    vault: vault
                )}
            
            for coin in coins {
                if coin.isNativeToken {
                    self.context.insert(coin)
                    vault.coins.append(coin)
                    
                    Task {
                        do{
                            try await CoinSelectionViewModel().addDiscoveredTokens(nativeToken: coin, to: vault)
                        } catch {
                            print("The coin \(coin.ticker) could not be added. \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}
