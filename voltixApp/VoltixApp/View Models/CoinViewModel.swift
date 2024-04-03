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
    
    func loadData(tx: SendTransaction) async {
        print("realoading data...")
        isLoading = true
        await CryptoPriceService.shared.fetchCryptoPrices()
        do {
            if tx.coin.chain.chainType == .UTXO {
                await utxo.fetchBlockchairData(for: tx)
                let coinName = tx.coin.chain.name.lowercased()
                let key = "\(tx.fromAddress)-\(coinName)"
                balanceUSD = utxo.blockchairData[key]?.address?.balanceInUSD ?? "US$ 0,00"
                coinBalance = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
            } else if tx.coin.chain == .ethereum {
                try await eth.getEthBalance(tx: tx)
                balanceUSD = tx.coin.balanceInUsd
                coinBalance = tx.coin.balanceString
                
            } else if tx.coin.chain == .thorChain {
                tx.gas = "0.02"
                
                let thorBalances = try await thor.fetchBalances(tx.fromAddress)
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.thorChain.name.lowercased()]?["usd"] {
                    balanceUSD = thorBalances.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
                }
                coinBalance = thorBalances.formattedRuneBalance() ?? "0.0"
            } else if tx.coin.chain == .bscChain {
                try await bsc.getBNBBalance(tx: tx)
                balanceUSD = tx.coin.balanceInUsd
                coinBalance = tx.coin.balanceString
            } else if tx.coin.chain == .avalanche {
                try await avax.getBalance(tx: tx)
                balanceUSD = tx.coin.balanceInUsd
                coinBalance = tx.coin.balanceString
            } else if tx.coin.chain == .gaiaChain {
                let atomBalance =  try await gaia.fetchBalances(tx.fromAddress)
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.priceProviderId]?["usd"] {
                    balanceUSD = atomBalance.atomBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
                }
                coinBalance = atomBalance.formattedAtomBalance() ?? "0.0"
                
            } else if tx.coin.chain == .solana {
                await sol.getSolanaBalance(tx:tx)
                await sol.fetchRecentBlockhash()
                balanceUSD = tx.coin.balanceInUsd
                coinBalance = tx.coin.balanceString
                await MainActor.run {
                    if let feeInLamports = sol.feeInLamports {
                        tx.gas = String(feeInLamports)
                    }
                }
            }
        }
        catch{
            print("error fetching data: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}
