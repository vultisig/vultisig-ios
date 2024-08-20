//
//  CoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/08/24.
//

import Foundation

@MainActor
struct CoinService {
    
    static func removeCoins(coins: [Coin], vault: Vault) async throws {
        for coin in coins {
            if let idx = vault.coins.firstIndex(where: { $0.ticker == coin.ticker && $0.chain == coin.chain }) {
                vault.coins.remove(at: idx)
            }
            
            await Storage.shared.delete(coin)
        }
    }
    
    static func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
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
    
    static func addToChain(assets: [CoinMeta], to vault: Vault) async throws {
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
    
    static func addToChain(asset: CoinMeta, to vault: Vault, priceProviderId: String?) async throws -> Coin? {
        let newCoin = try CoinFactory.create(asset: asset, vault: vault)
        if let priceProviderId {
            newCoin.priceProviderId = priceProviderId
        }
        // Save the new coin first
        // On IOS / IpadOS 18 , we have to user insert to insert the newCoin into modelcontext
        // otherwise it report an error "Illegal attempt to map a relationship containing temporary objects to its identifiers."
        await Storage.shared.insert([newCoin])
        try await Storage.shared.save()
        vault.coins.append(newCoin)
        return newCoin
    }
    
    static func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async {
        do {
            var tokens: [CoinMeta] = []
            switch nativeToken.chain.chainType {
            case .EVM :
                let service = try EvmServiceFactory.getService(forChain: nativeToken.chain)
                tokens = await service.getTokens(nativeToken: nativeToken)
            case .Solana:
                tokens = try await SolanaService.shared.fetchTokens(for: nativeToken.address)
            default:
                tokens = []
            }
            
            for token in tokens {
                do {
                    let existingCoin =  vault.coin(for: token)
                    if existingCoin != nil {
                        continue
                    }
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
