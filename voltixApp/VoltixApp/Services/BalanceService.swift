//
//  BalanceService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation

class BalanceService {
    static let shared = BalanceService()

    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let sol = SolanaService.shared
    private let gaia = GaiaService.shared
    private let maya = MayachainService.shared
    
    func balance(for coin: Coin) async throws -> (coinBalance: String, balanceFiat: String, balanceInFiatDecimal: Decimal) {
        
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
            coin.rawBalance = blockChairData?.address?.balance?.description ?? "0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            let balanceFiat = coin.balanceInFiat
            let coinBalance = coin.balanceString
            let balanceInFiatDecimal = coin.balanceInFiatDecimal
            return (coinBalance, balanceFiat, balanceInFiatDecimal)
            
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            coin.rawBalance = thorBalances.coinBalance(ticker: coin.ticker.lowercased()) ?? "0.0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            let balanceFiat = thorBalances.coinBalanceInFiat(price: coin.priceRate, coin: coin) ?? "$ 0,00"
            let coinBalance = thorBalances.formattedCoinBalance(coin:coin) ?? "0.0"
            let balanceInFiatDecimal = coin.balanceInFiatDecimal
            return (coinBalance, balanceFiat, balanceInFiatDecimal)
        case .mayaChain:
            let mayaBalances = try await maya.fetchBalances(coin.address)
            coin.rawBalance = mayaBalances.coinBalance(ticker: coin.ticker.lowercased()) ?? "0.0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            let balanceFiat = mayaBalances.coinBalanceInFiat(price: coin.priceRate, coin: coin) ?? "$ 0,00"
            let coinBalance = mayaBalances.formattedCoinBalance(coin:coin) ?? "0.0"
            let balanceInFiatDecimal = coin.balanceInFiatDecimal
            return (coinBalance, balanceFiat, balanceInFiatDecimal)
        case .solana:
            let (rawBalance,priceRate) = try await sol.getSolanaBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceFiat = coin.balanceInFiat
            let coinBalance = coin.balanceString
            let balanceInFiatDecimal = coin.balanceInFiatDecimal
            return (coinBalance, balanceFiat, balanceInFiatDecimal)
            
        case .ethereum, .avalanche, .bscChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (rawBalance,priceRate) = try await service.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceFiat = coin.balanceInFiat
            let coinBalance = coin.balanceString
            let balanceInFiatDecimal = coin.balanceInFiatDecimal
            return (coinBalance, balanceFiat, balanceInFiatDecimal)
            
        case .gaiaChain:
            let atomBalance =  try await gaia.fetchBalances(address: coin.address)
            var balanceFiat: String = .empty
            balanceFiat = atomBalance.coinBalanceInFiat(price: coin.priceRate,coin: coin) ?? "$ 0,00"
            coin.rawBalance = atomBalance.coinBalance(ticker: coin.ticker.lowercased()) ?? "0.0"
            let coinBalance = atomBalance.formattedCoinBalance(coin: coin) ?? "0.0"
            let balanceInFiatDecimal = coin.balanceInFiatDecimal
            return (coinBalance, balanceFiat, balanceInFiatDecimal)
        }
    }
}
