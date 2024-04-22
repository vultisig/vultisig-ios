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
    private let sol = SolanaService.shared
    private let gaia = GaiaService.shared
    private let kuji = KujiraService.shared
    private let maya = MayachainService.shared
    
    func balance(for coin: Coin) async throws -> (coinBalance: String, balanceFiat: String, balanceInFiatDecimal: Decimal) {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
            coin.rawBalance = blockChairData?.address?.balance?.description ?? "0"
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            coin.rawBalance = thorBalances.balance(denom: Chain.thorChain.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .solana:
            let (rawBalance,priceRate) = try await sol.getSolanaBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .merlin:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (rawBalance,priceRate) = try await service.getBalance(coin: coin)
            coin.rawBalance = rawBalance
            coin.priceRate = priceRate
        case .gaiaChain:
            let atomBalance =  try await gaia.fetchBalances(address: coin.address)
            coin.rawBalance = atomBalance.balance(denom: Chain.gaiaChain.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .kujira:
            let kujiBalance =  try await kuji.fetchBalances(address: coin.address)
            coin.rawBalance = kujiBalance.balance(denom: Chain.kujira.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        case .mayaChain:
            let mayaBalance = try await maya.fetchBalances(coin.address)
            coin.rawBalance = mayaBalance.balance(denom: coin.ticker.lowercased())
            coin.priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        }
        let balanceFiat = coin.balanceInFiat
        let coinBalance = coin.balanceString
        let balanceInFiatDecimal = coin.balanceInFiatDecimal
        return (coinBalance, balanceFiat, balanceInFiatDecimal)
    }
}
