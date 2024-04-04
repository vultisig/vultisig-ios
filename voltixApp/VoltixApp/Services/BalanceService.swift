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
    private let eth = EtherScanService.shared
    private let bsc = BSCService.shared
    private let avax = AvalancheService.shared
    private let sol = SolanaService.shared
    private let gaia = GaiaService.shared

    func balance(for coin: Coin) async throws -> (coinBalance: String, balanceUSD: String) {
        await CryptoPriceService.shared.fetchCryptoPrices()

        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let blockChairData = try await utxo.fetchBlockchairData(address: coin.address,coin: coin)
            let balanceUSD = blockChairData?.address?.balanceInUSD ?? "US$ 0,00"
            let coinBalance = blockChairData?.address?.balanceInBTC ?? "0.0"
            return (coinBalance, balanceUSD)

        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            var balanceUSD: String = .empty
            if let priceRateUsd = await CryptoPriceService.shared.cryptoPrices?.prices[Chain.thorChain.name.lowercased()]?["usd"] {
                balanceUSD = thorBalances.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
            }
            let coinBalance = thorBalances.formattedRuneBalance() ?? "0.0"
            return (coinBalance, balanceUSD)

        case .solana:
            let (rawBalance,priceRate) = try await sol.getSolanaBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)

        case .ethereum:
            let (rawBalance,priceRate) = await eth.getEthBalance(coin: coin,fromAddress: coin.address)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)

        case .avalanche:
            let (rawBalance,priceRate) = try await avax.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)

        case .bscChain:
            let (rawBalance,priceRate) = try await bsc.getBNBBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
            let balanceUSD = coin.balanceInUsd
            let coinBalance = coin.balanceString
            return (coinBalance, balanceUSD)

        case .gaiaChain:
            let atomBalance =  try await gaia.fetchBalances(address: coin.address)
            var balanceUSD: String = .empty
            if let priceRateUsd = await CryptoPriceService.shared.cryptoPrices?.prices[coin.priceProviderId]?["usd"] {
                balanceUSD = atomBalance.atomBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
            }
            let coinBalance = atomBalance.formattedAtomBalance() ?? "0.0"
            return (coinBalance, balanceUSD)
        }
    }
}
