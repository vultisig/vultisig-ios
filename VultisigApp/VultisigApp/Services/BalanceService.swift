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
    private let ton = TonService.shared
    private let osmo = OsmosisService.shared
    private let ripple = RippleService.shared
    
    private let terra = TerraService.shared
    private let terraClassic = TerraClassicService.shared
    
    private let noble = NobleService.shared
    
    private let cryptoPriceService = CryptoPriceService.shared
    
    func updateBalances(vault: Vault) async {
        do {
            try await cryptoPriceService.fetchPrices(vault: vault)
            
            await withTaskGroup(of: Void.self) { group in
                for coin in vault.coins {
                    group.addTask { [unowned self]  in
                        if !Task.isCancelled {
                            do {
                                let rawBalance = try await fetchBalance(for: coin)
                                try await updateCoin(coin, rawBalance: rawBalance)
                            } catch {
                                print("Fetch Balances error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            
            try await Storage.shared.save()
        } catch {
            print("Fetch Rates error: \(error.localizedDescription)")
        }
    }
    
    @MainActor func updateBalance(for coin: Coin) async {
        do {
            try await cryptoPriceService.fetchPrice(coin: coin)
            let rawBalance = try await fetchBalance(for: coin)
            try await updateCoin(coin, rawBalance: rawBalance)
            try await Storage.shared.save()
        } catch {
            print("Fetch Balance error: \(error.localizedDescription)")
        }
    }
}

private extension BalanceService {
    
    func fetchBalance(for coin: Coin) async throws -> String {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
            return blockChairData.address?.balance?.description ?? "0"
            
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            return thorBalances.balance(denom: Chain.thorChain.ticker.lowercased())
            
        case .solana:
            return try await sol.getSolanaBalance(coin: coin)
            
        case .sui:
            return try await sui.getBalance(coin: coin)
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain, .zksync:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            return try await service.getBalance(coin: coin)
            
            // COSMOS
        case .gaiaChain:
            let atomBalance = try await gaia.fetchBalances(coin: coin)
            return atomBalance.balance(denom: Chain.gaiaChain.ticker.lowercased(), coin: coin)
            
        case .dydx:
            let dydxBalance = try await dydx.fetchBalances(coin: coin)
            return dydxBalance.balance(denom: Chain.dydx.ticker.lowercased(), coin: coin)
            
        case .kujira:
            let kujiBalance = try await kuji.fetchBalances(coin: coin)
            return kujiBalance.balance(denom: Chain.kujira.ticker.lowercased(), coin: coin)
            
        case .osmosis:
            let osmoBalance = try await osmo.fetchBalances(coin: coin)
            return osmoBalance.balance(denom: Chain.osmosis.ticker.lowercased(), coin: coin)
            
        case .terra:
            let terraBalance = try await terra.fetchBalances(coin: coin)
            return terraBalance.balance(denom: "uluna", coin: coin)
            
        case .terraClassic:
            let terraClassicBalance = try await terraClassic.fetchBalances(coin: coin)
            return terraClassicBalance.balance(denom: "uluna", coin: coin)
            
        case .noble:
            let balance = try await noble.fetchBalances(coin: coin)
            return balance.balance(denom: Chain.noble.ticker.lowercased(), coin: coin)
         
            //
            
        case .mayaChain:
            let mayaBalance = try await maya.fetchBalances(coin.address)
            return mayaBalance.balance(denom: coin.ticker.lowercased())
            
        case .polkadot:
            return try await dot.getBalance(coin: coin)
            
        case .ton:
            return try await ton.getBalance(coin)
            
        case .ripple:
            return try await ripple.getBalance(coin)
        }
    }
    
    @MainActor func updateCoin(_ coin: Coin, rawBalance: String) async throws {
        guard coin.rawBalance != rawBalance else {
            return
        }
        
        coin.rawBalance = rawBalance
    }
}
