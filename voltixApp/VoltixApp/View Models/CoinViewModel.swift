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
		
		let coinName = tx.coin.chain.name.lowercased().replacingOccurrences(of: Chain.BitcoinCash.name.lowercased(), with: "bitcoin-cash")
		
		if  tx.coin.chain.chainType == ChainType.UTXO {
			await utxo.fetchBlockchairData(for: tx.fromAddress, coinName: coinName)
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			await eth.getEthInfo(for: tx.fromAddress)
		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
			await thor.fetchBalances(tx.fromAddress)
			await thor.fetchAccountNumber(tx.fromAddress)
		}
		await CryptoPriceService.shared.fetchCryptoPrices(for: "bitcoin,bitcoin-cash,dogecoin,litecoin,thorchain,solana", for: "usd")
		
		updateState(eth: eth, thor: thor, tx: tx)
		isLoading = false
	}
    
    private func fetchCryptoPrices() async {
        await CryptoPriceService.shared.fetchCryptoPrices(for: "bitcoin,litecoin,thorchain,solana", for: "usd")
    }
	
	private func updateState(eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction) {
		balanceUSD = "US$ 0,00"
		coinBalance = "0.0"
		
		let coinName = tx.coin.chain.name.lowercased().replacingOccurrences(of: Chain.BitcoinCash.name.lowercased(), with: "bitcoin-cash")
		let key: String = "\(tx.fromAddress)-\(coinName)"
		
		if  tx.coin.chain.chainType == ChainType.UTXO {
			self.balanceUSD = utxo.blockchairData?[key]?.address?.balanceInUSD ?? "US$ 0,00"
			self.coinBalance = utxo.blockchairData?[key]?.address?.balanceInBTC ?? "0.0"
		} else if tx.coin.chain.chainType == ChainType.EVM {
			tx.eth = eth.addressInfo
			if tx.coin.ticker.uppercased() == "ETH" {
				self.coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0"
				self.balanceUSD = eth.addressInfo?.ETH.balanceInUsd ?? "US$ 0,00"
			} else if let tokenInfo = tx.token {
				self.balanceUSD = tokenInfo.balanceInUsd
				self.coinBalance = tokenInfo.balanceString
			}
		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
			if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
				self.balanceUSD = thor.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
			}
			self.coinBalance = thor.formattedRuneBalance ?? "0.0"
		}
	}
}
