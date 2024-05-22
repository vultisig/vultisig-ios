//
//  BalanceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation

class BalanceService {
    static let shared = BalanceService()
    
    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let gaia = GaiaService.shared
    private let kuji = KujiraService.shared
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared
    
    private var balanceCache = ThreadSafeDictionary<String, (data: (rawBalance: String, priceRate: Double, coinBalance: String, balanceFiat: String, balanceInFiatDecimal: Decimal), timestamp: Date)>()
    
    func balance(for coin: Coin) async throws -> (coinBalance: String, balanceFiat: String, balanceInFiatDecimal: Decimal) {
        
        let cacheKey = "\(coin.chain.ticker).\(coin.ticker)-\(coin.address)"
        
        // Check the cache to avoid hitting the service APIs too many times.
        if let cachedData = await Utils.getCachedData(cacheKey: cacheKey, cache: balanceCache, timeInSeconds: 60) {
            print("Balance came from cache for \(cacheKey)")
            coin.rawBalance = cachedData.rawBalance
            coin.priceRate = cachedData.priceRate
            return (cachedData.coinBalance, cachedData.balanceFiat, cachedData.balanceInFiatDecimal)
        }
        
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
            coin.rawBalance = blockChairData?.address?.balance?.description ?? "0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            coin.rawBalance = thorBalances.balance(denom: Chain.thorChain.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .solana:
            let (rawBalance, priceRate) = try await sol.getSolanaBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
        case .sui:
            let (rawBalance, priceRate) = try await sui.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (rawBalance, priceRate) = try await service.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
        case .gaiaChain:
            let atomBalance = try await gaia.fetchBalances(address: coin.address)
            coin.rawBalance = atomBalance.balance(denom: Chain.gaiaChain.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .kujira:
            let kujiBalance = try await kuji.fetchBalances(address: coin.address)
            coin.rawBalance = kujiBalance.balance(denom: Chain.kujira.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .mayaChain:
            let mayaBalance = try await maya.fetchBalances(coin.address)
            coin.rawBalance = mayaBalance.balance(denom: coin.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .polkadot:
            let (rawBalance, priceRate) = try await dot.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
        }
        
        let balanceFiat = coin.balanceInFiat
        let coinBalance = coin.balanceString
        let balanceInFiatDecimal = coin.balanceInFiatDecimal
        
        let balanceData = (coin.rawBalance, coin.priceRate, coinBalance, balanceFiat, balanceInFiatDecimal)
        
        balanceCache.set(cacheKey, (data: balanceData, timestamp: Date()))
        
        return (coinBalance, balanceFiat, balanceInFiatDecimal)
    }
}
