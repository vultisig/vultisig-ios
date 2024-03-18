	//
	//  CoinViewModel.swift
	//  VoltixApp
	//
	//  Created by Amol Kumar on 2024-03-09.
	//

import Foundation

@MainActor class CoinViewModel: ObservableObject {
	@Published var isLoading = false
	@Published var balanceUSD = "US$ 0,00"
	@Published var coinBalance = "0.0"
	
	func loadData(utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction, blockchair: BlockchairService) async {
		print("realoading data...")
		isLoading = true
		
		// let utxosCoins = ["bitcoin", "litecoin", "dogecoin", "bitcoin-cash"]
		
		if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
			await blockchair.fetchBlockchairData(for: tx.fromAddress, coinName: Chain.Bitcoin.name.lowercased())
			await utxoBtc.fetchUnspentOutputs(for: tx.fromAddress)
		} else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
			await blockchair.fetchBlockchairData(for: tx.fromAddress, coinName: Chain.Litecoin.name.lowercased())
			await utxoLtc.fetchLitecoinUnspentOutputs(for: tx.fromAddress)
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			await eth.getEthInfo(for: tx.fromAddress)
		} else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
			await thor.fetchBalances(tx.fromAddress)
			await thor.fetchAccountNumber(tx.fromAddress)
		} else if tx.coin.chain.name.lowercased() == Chain.BitcoinCash.name.lowercased(){
			await blockchair.fetchBlockchairData(for: tx.fromAddress, coinName: "bitcoin-cash")
		} else if tx.coin.chain.name.lowercased() == Chain.Dogecoin.name.lowercased(){
			await blockchair.fetchBlockchairData(for: tx.fromAddress, coinName: Chain.Dogecoin.name.lowercased())
		}
		
		await CryptoPriceService.shared.fetchCryptoPrices(for: "bitcoin,bitcoin-cash,dogecoin,litecoin,thorchain,solana", for: "usd")
		
		updateState(utxoBtc: utxoBtc, utxoLtc: utxoLtc, eth: eth, thor: thor, tx: tx, blockchair: blockchair)
		isLoading = false
	}
	
	private func updateState(utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction, blockchair: BlockchairService) {
		balanceUSD = "US$ 0,00"
		coinBalance = "0.0"
		
		print(blockchair.blockchairData?[tx.coin.chain.name.lowercased()])
		
		if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {			
			self.balanceUSD = blockchair.blockchairData?[Chain.Bitcoin.name.lowercased()]?.address?.balanceInUSD ?? "US$ 0,00"
			self.coinBalance = blockchair.blockchairData?[Chain.Bitcoin.name.lowercased()]?.address?.balanceInBTC ?? "0.0"
			
		} else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
			if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
				self.balanceUSD = utxoLtc.walletData?.balanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
			}
			self.coinBalance = utxoLtc.walletData?.balanceInLTC ?? "0.0"
			
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
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
