//
//  CoinViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-09.
//


import Foundation
import SwiftUI

@MainActor
class CoinViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var balanceUSD: String? = nil
    @Published var coinBalance: String? = nil
    
    private var utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    
    func loadData(eth: EthplorerAPIService, tx: SendTransaction) async {
        print("realoading data...")
        isLoading = true
        await CryptoPriceService.shared.fetchCryptoPrices()
        
        let coinName = tx.coin.chain.name.lowercased()
        if tx.coin.chain.chainType == ChainType.UTXO {
            await utxo.fetchBlockchairData(for: tx.fromAddress, coinName: coinName)
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            await eth.getEthInfo(for: tx.fromAddress)
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
            self.updateState(eth: eth, tx: tx)
        }
        isLoading = false
    }
    
    public func updateState(eth: EthplorerAPIService, tx: SendTransaction) {
        let coinName = tx.coin.chain.name.lowercased()
        let key = "\(tx.fromAddress)-\(coinName)"
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            balanceUSD = utxo.blockchairData[key]?.address?.balanceInUSD ?? "US$ 0,00"
            coinBalance = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
        } else if tx.coin.chain.chainType == ChainType.EVM {
            tx.eth = eth.addressInfo
            if tx.coin.ticker.uppercased() == "ETH" {
                coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0"
                balanceUSD = eth.addressInfo?.ETH.balanceInUsd ?? "US$ 0,00"
            } else if let tokenInfo = tx.token {
                balanceUSD = tokenInfo.balanceInUsd
                coinBalance = tokenInfo.balanceString
            }
        }
    }
}
