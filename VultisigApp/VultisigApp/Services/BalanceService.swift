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
    private let tron = TronService.shared
    
    private let terra = TerraService.shared
    private let terraClassic = TerraClassicService.shared
    
    private let noble = NobleService.shared
    private let akash = AkashService.shared
    
    private let cryptoPriceService = CryptoPriceService.shared
    
    func updateBalances(vault: Vault) async {
        
        do {
            try await cryptoPriceService.fetchPrices(vault: vault)
        } catch {
            print("error \(error)")
            print("Fetch Rates error: \(error.localizedDescription)")
        }
        
        do {
            await withTaskGroup(of: Void.self) { group in
                for coin in vault.coins {
                    group.addTask { [unowned self]  in
                        if !Task.isCancelled {
                            do {
                                let rawBalance = try await fetchBalance(for: coin)
                                try await updateCoin(coin, rawBalance: rawBalance)
                                
                                let stakedBalance = try await fetchStakedBalance(for: coin)
                                try await updateCoin(coin, stakedBalance: stakedBalance)
                            } catch {
                                print("Fetch Balances error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            
            try await Storage.shared.save()
        } catch {
            print("Update Balances error: \(error.localizedDescription)")
        }
    }
    
    @MainActor func updateBalance(for coin: Coin) async {
        do {
            try await cryptoPriceService.fetchPrice(coin: coin)
        } catch {
            print("Fetch Price error: \(error.localizedDescription)")
        }
        do {
            let rawBalance = try await fetchBalance(for: coin)
            try await updateCoin(coin, rawBalance: rawBalance)
            
            let stakedBalance = try await fetchStakedBalance(for: coin)
            try await updateCoin(coin, stakedBalance: stakedBalance)
            
            try await Storage.shared.save()
        } catch {
            print("Fetch Balance error: \(error.localizedDescription)")
        }
    }
}

private extension BalanceService {
    
    func fetchStakedBalance(for coin: Coin) async throws -> String {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            return .zero
            
        case .thorChain:
            // Handle TCY staked balance
            if coin.ticker.caseInsensitiveCompare("TCY") == .orderedSame {
                let tcyStakedBalance = await thor.fetchTcyStakedAmount(address: coin.address)
                return tcyStakedBalance.description
            }

            // Handle merge account balances for non-native tokens
            if !coin.isNativeToken {
                let mergedAccounts = await thor.fetchMergeAccounts(address: coin.address)
                
                if let matchedAccount = mergedAccounts.first(where: {
                    $0.pool.mergeAsset.metadata.symbol.caseInsensitiveCompare(coin.ticker) == .orderedSame
                }) {
                    let amountInDecimal = matchedAccount.size.amount.toDecimal() / Decimal(100_000_000)
                    return amountInDecimal.description
                }
            }

            // Fallback return value
            return "0"
            
        case .solana:
            return .zero
            
        case .sui:
            return .zero
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync, .ethereumSepolia:
            return .zero
            
        case .gaiaChain:
            return .zero
            
        case .dydx:
            return .zero
            
        case .kujira:
            return .zero
            
        case .osmosis:
            return .zero
            
        case .terra:
            return .zero
            
        case .terraClassic:
            return .zero
            
        case .noble:
            return .zero
         
        case .mayaChain:
            return .zero
            
        case .polkadot:
            return .zero
            
        case .ton:
            return .zero
            
        case .ripple:
            return .zero
            
        case .akash:
            return .zero
            
        case .tron:
            return .zero
        
        }
    }

    func fetchBalance(for coin: Coin) async throws -> String {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
            return blockChairData.address?.balance?.description ?? "0"
            
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            return thorBalances.balance(denom: Chain.thorChain.ticker.lowercased(), coin: coin)
            
        case .solana:
            return try await sol.getSolanaBalance(coin: coin)
            
        case .sui:
            return try await sui.getBalance(coin: coin)
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync,.ethereumSepolia:
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
            
        case .akash:
            let balance = try await akash.fetchBalances(coin: coin)
            return balance.balance(denom: Chain.akash.ticker.lowercased(), coin: coin)
            
        case .tron:
            return try await tron.getBalance(coin: coin)
         
            //
        
        }
    }
    
    @MainActor func updateCoin(_ coin: Coin, rawBalance: String) async throws {
        guard coin.rawBalance != rawBalance else {
            return
        }
        
        coin.rawBalance = rawBalance
    }
    
    @MainActor func updateCoin(_ coin: Coin, stakedBalance: String) async throws {
        guard coin.stakedBalance != stakedBalance else {
            return
        }
        
        coin.stakedBalance = stakedBalance
    }
}
