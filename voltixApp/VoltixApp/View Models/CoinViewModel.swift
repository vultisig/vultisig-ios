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
    
    func loadData(uxto: UnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction) async {
            print("realoading data...")
            isLoading = true
            
            if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
                await uxto.fetchUnspentOutputs(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                await eth.getEthInfo(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                await thor.fetchBalances(tx.fromAddress)
                await thor.fetchAccountNumber(tx.fromAddress)
            }
            
            await CryptoPriceService.shared.fetchCryptoPrices(for: "bitcoin,thorchain", for: "usd")
            
            updateState(uxto: uxto, eth: eth, thor: thor, tx: tx)
            isLoading = false
    }
    
    private func updateState(uxto: UnspentOutputsService, eth: EthplorerAPIService, thor: ThorchainService, tx: SendTransaction) {
        balanceUSD = "US$ 0,00"
        coinBalance = "0.0"
        
        if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
                self.balanceUSD = uxto.walletData?.balanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
            }
            self.coinBalance = uxto.walletData?.balanceInBTC ?? "0.0"
            
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
