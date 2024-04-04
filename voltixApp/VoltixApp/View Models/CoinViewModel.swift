//
//  CoinViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI
import BigInt

@MainActor
class CoinViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var balanceUSD: String? = nil
    @Published var coinBalance: String? = nil
    
    private var utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let eth = EtherScanService.shared
    private let bsc = BSCService.shared
    private let avax = AvalancheService.shared
    private let sol = SolanaService.shared
    private let gaia = GaiaService.shared
    
    func loadData(coin: Coin) async {
        isLoading = true
        defer { isLoading = false }
        
        await CryptoPriceService.shared.fetchCryptoPrices()
        
        do {
            switch coin.chain {
            case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
                let blockChairData = try await utxo.fetchBlockchairData(address: coin.address,coin: coin)
                balanceUSD = blockChairData?.address?.balanceInUSD ?? "US$ 0,00"
                coinBalance = blockChairData?.address?.balanceInBTC ?? "0.0"
                
            case .thorChain:
                let thorBalances = try await thor.fetchBalances(coin.address)
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.thorChain.name.lowercased()]?["usd"] {
                    balanceUSD = thorBalances.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
                }
                coinBalance = thorBalances.formattedRuneBalance() ?? "0.0"
                
            case .solana:
                let (rawBalance,priceRate) = try await sol.getSolanaBalance(coin: coin)
                coin.rawBalance = rawBalance
                coin.priceRate = priceRate
                balanceUSD = coin.balanceInUsd
                coinBalance = coin.balanceString
                
            case .ethereum:
                let (rawBalance,priceRate) = await eth.getEthBalance(coin: coin,fromAddress: coin.address)
                coin.rawBalance = rawBalance
                coin.priceRate = priceRate
                balanceUSD = coin.balanceInUsd
                coinBalance = coin.balanceString
            case .avalanche:
                let (rawBalance,priceRate) = try await avax.getBalance(coin: coin)
                coin.rawBalance = rawBalance
                coin.priceRate = priceRate
                balanceUSD = coin.balanceInUsd
                coinBalance = coin.balanceString
                
            case .bscChain:
                let (rawBalance,priceRate) = try await bsc.getBNBBalance(coin: coin)
                coin.rawBalance = rawBalance
                coin.priceRate = priceRate
                balanceUSD = coin.balanceInUsd
                coinBalance = coin.balanceString
                
            case .gaiaChain:
                let atomBalance =  try await gaia.fetchBalances(address: coin.address)
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[coin.priceProviderId]?["usd"] {
                    balanceUSD = atomBalance.atomBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
                }
                coinBalance = atomBalance.formattedAtomBalance() ?? "0.0"
            }
        }
        catch {
            print("error fetching data: \(error.localizedDescription)")
        }
    }
}
