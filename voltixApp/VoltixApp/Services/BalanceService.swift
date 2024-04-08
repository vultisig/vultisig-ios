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
    
    func balance(for coin: Coin) async throws -> (coinBalance: String, balanceUSD: String) {
        
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let blockChairData = try await utxo.fetchBlockchairData(address: coin.address,coin: coin)
            coin.rawBalance = blockChairData?.address?.balance?.description ?? "0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)
            
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            coin.rawBalance = thorBalances.runeBalance() ?? "0.0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
            let balanceUSD = thorBalances.runeBalanceInUSD(usdPrice: coin.priceRate) ?? "$ 0,00"
            let coinBalance = thorBalances.formattedRuneBalance() ?? "0.0"
            return (coinBalance, balanceUSD)
            
        case .solana:
            let (rawBalance,priceRate) = try await sol.getSolanaBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)
            
        case .ethereum, .avalanche, .bscChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (rawBalance,priceRate) = try await service.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)
            
        case .gaiaChain:
            let atomBalance =  try await gaia.fetchBalances(address: coin.address)
            var balanceUSD: String = .empty
            balanceUSD = atomBalance.atomBalanceInUSD(usdPrice: coin.priceRate) ?? "$ 0,00"
            coin.rawBalance = atomBalance.atomBalance() ?? "0.0"
            let coinBalance = atomBalance.formattedAtomBalance() ?? "0.0"
            return (coinBalance, balanceUSD)
        }
    }
}
