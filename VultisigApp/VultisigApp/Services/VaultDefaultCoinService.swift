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
    
    init(context: ModelContext){
        self.context = context
    }
    
    func setDefaultCoinsOnce(vault: Vault) {
        semaphore.wait()
        defer {
            semaphore.signal()
        }
        setDefaultCoins(for: vault)
    }
    
    func setDefaultCoins(for vault: Vault) {
        // Add default coins when the vault doesn't have any coins in it
        print("set default chains to vault")
        if vault.coins.count == 0 {
            let chains: [CoinMeta]
            
            chains = TokensStore.TokenSelectionAssets
                    .filter { asset in baseDefaultChains.contains(where: { $0 == asset.chain }) }
            
            let coins = chains
                .compactMap { try? CoinFactory.create(
                    asset: $0,
                    publicKeyECDSA: vault.pubKeyECDSA,
                    publicKeyEdDSA: vault.pubKeyEdDSA,
                    hexChainCode: vault.hexChainCode
                )}
            
            for coin in coins {
                if coin.isNativeToken {
                    self.context.insert(coin)
                    vault.coins.append(coin)
                    
                    Task {
                        await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
                    }
                }
            }
            
            // Enable default Defi chains
            vault.defiChains = coins.map(\.chain).filter { CoinAction.defiChains.contains($0) }
        }
    }
}
