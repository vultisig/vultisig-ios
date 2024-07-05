//
//  CoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 05/07/24.
//

import Foundation

@MainActor
class CoinService {
    
    static let shared = CoinService()
    
    func removeCoins(coins: [Coin], vault: Vault) async throws {
        for coin in coins {
            if let idx = vault.coins.firstIndex(where: { $0.ticker == coin.ticker && $0.chain == coin.chain }) {
                vault.coins.remove(at: idx)
            }
            
            await Storage.shared.delete(coin)
        }
    }
    
    func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
        do {
            let removedCoins = vault.coins.filter { coin in
                !selection.contains(where: { $0.ticker == coin.ticker && $0.chain == coin.chain})
            }
            let nativeCoins = removedCoins.filter { $0.isNativeToken }
            let allTokens = vault.coins.filter { coin in
                nativeCoins.contains(where: { $0.chain == coin.chain }) && !coin.isNativeToken
            }
            
            try await removeCoins(coins: removedCoins, vault: vault)
            try await removeCoins(coins: nativeCoins, vault: vault)
            try await removeCoins(coins: allTokens, vault: vault)
            
            // remove all native tokens and also the tokens so they are not added again
            let filteredSelection = selection.filter{ selection in
                !nativeCoins.contains(where: { selection.ticker == $0.ticker && selection.chain == $0.chain}) &&
                !allTokens.contains(where: { selection.ticker == $0.ticker && selection.chain == $0.chain})
            }
            
            var newCoins: [CoinMeta] = []
            for asset in filteredSelection {
                if !vault.coins.contains(where: { $0.ticker == asset.ticker && $0.chain == asset.chain}) {
                    newCoins.append(asset)
                    print("asset ticker \(asset.ticker)")
                }
            }
            
            try await addToChain(assets: newCoins, to: vault)
            
        } catch {
            print("fail to save asset,\(error)")
        }
    }
    
    func addToChain(assets: [CoinMeta], to vault: Vault) async throws {
        if let coin = assets.first, coin.chain.chainType == .EVM, !coin.isNativeToken {
            for asset in assets {
                _ = try await addToChain(asset: asset, to: vault, priceProviderId: nil)
            }
        } else {
            for asset in assets {
                if let newCoin = try await addToChain(asset: asset, to: vault, priceProviderId: asset.priceProviderId) {
                    print("Add discovered tokens for \(asset.ticker) on the chain \(asset.chain.name)")
                    await addDiscoveredTokens(nativeToken: newCoin, to: vault)
                }
            }
        }
    }
    
    func addToChain(asset: CoinMeta, to vault: Vault, priceProviderId: String?) async throws -> Coin? {
        let newCoin = try CoinFactory.create(asset: asset, vault: vault)
        if let priceProviderId {
            newCoin.priceProviderId = priceProviderId
        }
        // Save the new coin first
        try await Storage.shared.save(newCoin)
        vault.coins.append(newCoin)
        return newCoin
    }
    
    func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async  {
        do {
            // Only auto discovery for EVM type chains
            if nativeToken.chain.chainType != .EVM {
                return
            }
            let service = try EvmServiceFactory.getService(forCoin: nativeToken)
            let tokens = await service.getTokens(nativeToken: nativeToken)
            
            for token in tokens {
                do {
                    _ = try await addToChain(asset: token, to: vault, priceProviderId: nil)
                } catch {
                    print("Error adding the token \(token.ticker) service: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error fetching service: \(error.localizedDescription)")
        }
    }
}
