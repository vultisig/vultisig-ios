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
            let defaultChains = getDefaultChains(for: vault)
            let chains: [CoinMeta] = TokensStore.TokenSelectionAssets
                    .filter { asset in defaultChains.contains(where: { $0 == asset.chain }) }
            
            let coins = chains
                .compactMap { c in
                    let pubKey = vault.chainPublicKeys.first { $0.chain == c.chain}?.publicKeyHex
                    let isDerived = pubKey != nil
                    return try? CoinFactory.create(
                        asset: c,
                        publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                        publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                        hexChainCode: vault.hexChainCode,
                        isDerived: isDerived
                    )
                }
            
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
            vault.defiChains = Array(Set(coins.map(\.chain).filter { CoinAction.defiChains.contains($0) }))
        }
    }
    
    func getDefaultChains(for vault: Vault) -> [Chain] {
        // For KeyImport we can only add derived chains
        if vault.libType == .KeyImport {
            return vault.chainPublicKeys.map(\.chain)
        } else {
            return baseDefaultChains
        }
    }
}
