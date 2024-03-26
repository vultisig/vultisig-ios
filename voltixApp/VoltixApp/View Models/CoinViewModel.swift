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

    func loadData(tx: SendTransaction) async {
        print("realoading data...")
        isLoading = true
        await CryptoPriceService.shared.fetchCryptoPrices()
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                async let sats = utxo.fetchSatsPrice(tx: tx)
                async let blockchairData: () = utxo.fetchBlockchairData(for: tx)
                
                tx.gas = String(try await sats)
                _ = await blockchairData
            } catch {
                print("error fetching data: \(error.localizedDescription)")
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            do {
                try await eth.getEthInfo(tx: tx)
                balanceUSD = tx.coin.balanceInUsd
                coinBalance = tx.coin.balanceString                
            } catch {
                print("error fetching eth balances:\(error.localizedDescription)")
            }
            
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            tx.gas = "0.02"
            do{
                let thorBalances = try await thor.fetchBalances(tx.fromAddress)
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                    balanceUSD = thorBalances.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
                }
                coinBalance = thorBalances.formattedRuneBalance() ?? "0.0"
            }catch{
                print("error fetching thorchain balances:\(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async {
            self.updateState(tx: tx)
        }
        isLoading = false
    }
    
    public func updateState(tx: SendTransaction) {
        let coinName = tx.coin.chain.name.lowercased()
        let key = "\(tx.fromAddress)-\(coinName)"
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            balanceUSD = utxo.blockchairData[key]?.address?.balanceInUSD ?? "US$ 0,00"
            coinBalance = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
        }
    }
}
