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
	
    func loadData(eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction) async {
        print("realoading data...")
        isLoading = true
		
        let coinName = tx.coin.chain.name.lowercased()
		
        if tx.coin.chain.chainType == ChainType.UTXO {
            await utxo.fetchBlockchairData(for: tx.fromAddress, coinName: coinName)
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            await eth.getEthInfo(for: tx.fromAddress)
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            await thor.fetchBalances(tx.fromAddress)
            await thor.fetchAccountNumber(tx.fromAddress)
        }
		await CryptoPriceService.shared.fetchCryptoPrices()
		DispatchQueue.main.async {
			self.updateState(eth: eth, thor: thor, tx: tx)
		}
        isLoading = false
    }
	
    public func updateState(eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction) {
        balanceUSD = "US$ 0,00"
        coinBalance = "0.0"
		
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
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                balanceUSD = thor.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
            }
            coinBalance = thor.formattedRuneBalance ?? "0.0"
        }
    }
}
