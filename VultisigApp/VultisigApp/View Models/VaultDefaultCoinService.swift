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
    let defaultChains = [Chain.bitcoin, Chain.ethereum, Chain.thorChain, Chain.solana]
    
    init(context:ModelContext){
        self.context = context
    }
    func setDefaultCoinsOnce(vault: Vault) {
        semaphore.wait()
        Task{
            await setDefaultCoins(for: vault)
            semaphore.signal()
        }
    }
    func setDefaultCoins(for vault: Vault) async {
        // Add default coins when the vault doesn't have any coins in it
        if vault.coins.count == 0 {
            let coins = TokensStore.TokenSelectionAssets
                .filter { asset in defaultChains.contains(where: { $0 == asset.chain }) }
                .filter { $0.isNativeToken }
                .compactMap { try? CoinFactory.create(
                    asset: $0,
                    vault: vault
                )}

            await Storage.shared.insert(coins)
            vault.coins += coins
        }
    }
}
