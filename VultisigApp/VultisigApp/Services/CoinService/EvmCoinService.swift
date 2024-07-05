//
//  EvmCoinService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 05/07/24.
//

import Foundation

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
