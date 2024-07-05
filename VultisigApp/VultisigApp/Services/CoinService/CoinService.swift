//
//  CoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 05/07/24.
//

import Foundation

@MainActor
class CoinService {
    
    func removeCoins(coins: [Coin], vault: Vault) async throws {
        for coin in coins {
            if let idx = vault.coins.firstIndex(where: { $0.ticker == coin.ticker && $0.chain == coin.chain }) {
                vault.coins.remove(at: idx)
            }
            
            await Storage.shared.delete(coin)
        }
    }
    
    func addToChain(assets: [CoinMeta], to vault: Vault) async throws {
        for asset in assets {
            let _ = try await addToChain(asset: asset, to: vault, priceProviderId: asset.priceProviderId)
        }
    }
    
    func addToChain(asset: CoinMeta, to vault: Vault, priceProviderId: String?) async throws -> Coin? {
        let newCoin = try CoinFactory.create(asset: asset, vault: vault)
        if let priceProviderId {
            newCoin.priceProviderId = priceProviderId
        }
        try await Storage.shared.save(newCoin)
        vault.coins.append(newCoin)
        return newCoin
    }
    
    func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async {}
    
}

extension CoinService: Hashable {
    static func == (lhs: CoinService, rhs: CoinService) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
