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
    private let dydx = DydxService.shared
    private let kuji = KujiraService.shared
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared

    private let cryptoPriceService = CryptoPriceService.shared

    func updateBalances(vault: Vault) async {

        do {
            try await cryptoPriceService.fetchPrices(vault: vault)
        } catch {
            fatalError(error.localizedDescription)
        }

        await withTaskGroup(of: Void.self) { group in
            for coin in vault.coins {
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
            let rawBalance: String

            switch coin.chain {
            case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
                let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
                rawBalance = blockChairData?.address?.balance?.description ?? "0"

            case .thorChain:
                let thorBalances = try await thor.fetchBalances(coin.address)
                rawBalance = thorBalances.balance(denom: Chain.thorChain.ticker.lowercased())

            case .solana:
                rawBalance = try await sol.getSolanaBalance(coin: coin)

            case .sui:
                rawBalance = try await sui.getBalance(coin: coin)

            case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .zksync:
                let service = try EvmServiceFactory.getService(forChain: coin.chain)
                rawBalance = try await service.getBalance(coin: coin)

            case .gaiaChain:
                let atomBalance = try await gaia.fetchBalances(address: coin.address)
                rawBalance = atomBalance.balance(denom: Chain.gaiaChain.ticker.lowercased())

            case .dydx:
                let dydxBalance = try await dydx.fetchBalances(address: coin.address)
                rawBalance = dydxBalance.balance(denom: Chain.dydx.ticker.lowercased())

            case .kujira:
                let kujiBalance = try await kuji.fetchBalances(address: coin.address)
                rawBalance = kujiBalance.balance(denom: Chain.kujira.ticker.lowercased())

            case .mayaChain:
                let mayaBalance = try await maya.fetchBalances(coin.address)
                rawBalance = mayaBalance.balance(denom: coin.ticker.lowercased())

            case .polkadot:
                rawBalance = try await dot.getBalance(coin: coin)
            }
            
            try await updateCoin(coin, rawBalance: rawBalance)
        } catch {
            print("BalanceService error: \(error.localizedDescription)")
        }
    }
}

private extension BalanceService {
    
    @MainActor func updateCoin(_ coin: Coin, rawBalance: String) async throws {
        guard coin.rawBalance != rawBalance else { return }
        coin.rawBalance = rawBalance
        // Swift Data persists on disk io, that is slower than the cache on KEY VALUE RAM
        try await Storage.shared.save()
    }
}
