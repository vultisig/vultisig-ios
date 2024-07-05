//
//  CoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 05/07/24.
//

import Foundation

@MainActor
class VaultService {
    
    static func saveAssets(for vault: Vault, selection: Set<CoinMeta>) async {
        do {
            
            let service = CoinService()
            
            let removedCoins = vault.coins.filter { coin in
                !selection.contains(where: { $0.ticker == coin.ticker && $0.chain == coin.chain})
            }
            let nativeCoins = removedCoins.filter { $0.isNativeToken }
            let allTokens = vault.coins.filter { coin in
                nativeCoins.contains(where: { $0.chain == coin.chain }) && !coin.isNativeToken
            }
            
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
                    print("asset ticker \(asset.ticker)")
                }
            }
            
            try await service.addToChain(assets: newCoins, to: vault)
            
        } catch {
            print("fail to save asset,\(error)")
        }
    }
    
}


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
            let _ = try await CoinServiceFactory.getService(for: asset).addToChain(asset: asset, to: vault, priceProviderId: asset.priceProviderId)
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

@MainActor
class EvmCoinService: CoinService {
    
    override func addDiscoveredTokens(nativeToken: Coin, to vault: Vault) async {
        do {
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
    
    override func addToChain(assets: [CoinMeta], to vault: Vault) async throws {
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
    
}

@MainActor
class UtxoCoinService: CoinService {}

@MainActor
class CosmosCoinService: CoinService {}

@MainActor
class CoinServiceFactory {
    
    static func getService(for coin: Coin) -> CoinService {
        switch coin.chain.chainType {
        case .EVM:
            return EvmCoinService()
        case .UTXO:
            return UtxoCoinService()
        case .Cosmos:
            return CosmosCoinService()
        default:
            return CoinService()
        }
    }
    
    static func getService(for coin: CoinMeta) -> CoinService {
        switch coin.chain.chainType {
        case .EVM:
            return EvmCoinService()
        case .UTXO:
            return UtxoCoinService()
        case .Cosmos:
            return CosmosCoinService()
        default:
            return CoinService()
        }
    }
    
}
