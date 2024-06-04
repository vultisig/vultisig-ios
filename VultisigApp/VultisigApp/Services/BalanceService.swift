//
//  BalanceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 04.04.2024.
//

import Foundation
import SwiftData

class BalanceService {
    static let shared = BalanceService()
    
    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let gaia = GaiaService.shared
    private let kuji = KujiraService.shared
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared

    func updateBalances(coins: [Coin]) async {
        await withTaskGroup(of: Void.self) { group in
            for coin in coins {
                group.addTask { [unowned self]  in
                    if !Task.isCancelled {
                        await updateBalance(for: coin)
                    }
                }
            }
        }
    }

    @MainActor func updateBalance(for coin: Coin) async {
        do {
            switch coin.chain {
            case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
                let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
                let rawBalance = blockChairData?.address?.balance?.description ?? "0"
                let priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .thorChain:
                let thorBalances = try await thor.fetchBalances(coin.address)
                let rawBalance = thorBalances.balance(denom: Chain.thorChain.ticker.lowercased())
                let priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .solana:
                let (rawBalance, priceRate) = try await sol.getSolanaBalance(coin: coin)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .sui:
                let (rawBalance,priceRate) = try await sui.getBalance(coin: coin)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .zksync:
                let service = try EvmServiceFactory.getService(forCoin: coin)
                let (rawBalance, priceRate) = try await service.getBalance(coin: coin)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .gaiaChain:
                let atomBalance =  try await gaia.fetchBalances(address: coin.address)
                let rawBalance = atomBalance.balance(denom: Chain.gaiaChain.ticker.lowercased())
                let priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .kujira:
                let kujiBalance =  try await kuji.fetchBalances(address: coin.address)
                let rawBalance = kujiBalance.balance(denom: Chain.kujira.ticker.lowercased())
                let priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .mayaChain:
                let mayaBalance = try await maya.fetchBalances(coin.address)
                let rawBalance = mayaBalance.balance(denom: coin.ticker.lowercased())
                let priceRate = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            case .polkadot:
                let (rawBalance,priceRate) = try await dot.getBalance(coin: coin)
                try await updateCoin(coin, rawBalance: rawBalance, priceRate: priceRate)
            }
        }
        catch {
            print("BalanceService error: \(error.localizedDescription)")
        }
    }
}

private extension BalanceService {

    @MainActor func updateCoin(_ coin: Coin, rawBalance: String, priceRate: Double) async throws {
        coin.rawBalance = rawBalance
        coin.priceRate = priceRate
        try await Storage.shared.save(coin)
    }
}
