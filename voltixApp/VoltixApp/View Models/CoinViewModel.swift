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
	@Published var ethAddressInfo: EthAddressInfo = EthAddressInfo()
	
	private var utxo = BlockchairService.shared
	private let thor = ThorchainService.shared
	private let eth = EtherScanService.shared
	
		//TODO: Something is wrong with this load data
		//TODO: We need to check because it is called at least 5x
	func loadData(tx: SendTransaction) async {
		print("realoading data...")
		isLoading = true
		await CryptoPriceService.shared.fetchCryptoPrices()
		
		let coinName = tx.coin.chain.name.lowercased()
		if tx.coin.chain.chainType == ChainType.UTXO {
			await utxo.fetchBlockchairData(for: tx.fromAddress, coinName: coinName)
		} else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
			do {
				
				print("The loadData ETH is called \(tx.coin.ticker)")
				
				// Start fetching all information concurrently
				async let ethAddressInfo = eth.getEthInfo(for: tx.fromAddress)
				async let gasPrice = eth.fetchGasPrice()
				async let nonce = eth.fetchNonce(address: tx.fromAddress)
				
				tx.eth = try await ethAddressInfo
				tx.gas = String(try await gasPrice)
				tx.nonce = try await nonce
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
		} else if tx.coin.chain.chainType == ChainType.EVM {
			tx.eth = self.ethAddressInfo
			if tx.coin.ticker.uppercased() == "ETH" {
				coinBalance = self.ethAddressInfo.balanceString
				balanceUSD = self.ethAddressInfo.balanceInUsd
			} else if let tokenInfo = tx.token {
				balanceUSD = tokenInfo.balanceInUsd
				coinBalance = tokenInfo.balanceString
			}
		}
	}
}
