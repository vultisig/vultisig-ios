//
//  BalanceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation
import SwiftData

class BalanceService {
    static let shared = BalanceService()
    
    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let gaia = GaiaService.shared
    private let dydx = DydxService.shared
    private let kuji = KujiraService.shared
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared
    
    private struct CachedValue {
        let rawBalance: String
        let priceRate: Double
    }
    
    private var cache: ThreadSafeDictionary<String, (data: CachedValue, timestamp: Date)> = ThreadSafeDictionary()
    
    private let CACHE_TIMEOUT_IN_SECONDS: Double = 120 // 2 minutes
    
    private func cacheKey(coin: Coin) -> String {
        "\(coin.ticker)-\(coin.contractAddress)-\(coin.chain.rawValue)-\(coin.address)"
    }
    
    func updateBalances(vault: Vault) async {
        await withTaskGroup(of: Void.self) { group in
            for coin in vault.coins {
                group.addTask { [unowned self]  in
                    if !Task.isCancelled {
                        await updateBalance(for: coin)
                    }
                }
            }
        }
    }
    
    @MainActor func updateBalance(for coin: Coin) async {
        do {
            
            if let cachedValue = await Utils.getCachedData(cacheKey: cacheKey(coin: coin), cache: cache, timeInSeconds: CACHE_TIMEOUT_IN_SECONDS) {
                coin.rawBalance = cachedValue.rawBalance
                coin.priceRate = cachedValue.priceRate
                return
            }
            
            var rawBalance: String = .empty
            var priceRate = Double.zero
            
            switch coin.chain {
            case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
                let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
                rawBalance = blockChairData?.address?.balance?.description ?? "0"
                priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                
            case .thorChain:
                let thorBalances = try await thor.fetchBalances(coin.address)
                rawBalance = thorBalances.balance(denom: Chain.thorChain.ticker.lowercased())
                priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                
            case .solana:
                (rawBalance, priceRate) = try await sol.getSolanaBalance(coin: coin)
                
            case .sui:
                (rawBalance, priceRate) = try await sui.getBalance(coin: coin)
                
            case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .zksync:
                let service = try EvmServiceFactory.getService(forCoin: coin)
                (rawBalance, priceRate) = try await service.getBalance(coin: coin)
                
            case .gaiaChain:
                let atomBalance = try await gaia.fetchBalances(address: coin.address)
                rawBalance = atomBalance.balance(denom: Chain.gaiaChain.ticker.lowercased())
                priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                
            case .dydx:
                let dydxBalance = try await dydx.fetchBalances(address: coin.address)
                rawBalance = dydxBalance.balance(denom: Chain.dydx.ticker.lowercased())
                priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                
            case .kujira:
                let kujiBalance = try await kuji.fetchBalances(address: coin.address)
                rawBalance = kujiBalance.balance(denom: Chain.kujira.ticker.lowercased())
                priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                
            case .mayaChain:
                let mayaBalance = try await maya.fetchBalances(coin.address)
                rawBalance = mayaBalance.balance(denom: coin.ticker.lowercased())
                priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                
            case .polkadot:
                (rawBalance, priceRate) = try await dot.getBalance(coin: coin)
            }
            
            try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
        } catch {
            print("BalanceService error: \(error.localizedDescription)")
        }
    }
}

private extension BalanceService {
    
    @MainActor func updateCoin(_ coin: Coin, rawBalance: String, priceRate: Double) async throws {
        guard coin.rawBalance != rawBalance && coin.priceRate != priceRate else { return }
        coin.rawBalance = rawBalance
        coin.priceRate = priceRate
        // Swift Data persists on disk io, that is slower than the cache on KEY VALUE RAM
        try await Storage.shared.save(coin)
        cache.set(cacheKey(coin: coin), (data: CachedValue(rawBalance: rawBalance, priceRate: priceRate), timestamp: Date()))
    }
}
