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
    private let maya = MayachainService.shared
    private let dot = PolkadotService.shared
    private let ton = TonService.shared
    private let ripple = RippleService.shared
    private let tron = TronService.shared
    private let cardano = CardanoService.shared
    
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
            
            try Storage.shared.save()
        } catch {
            print("Fetch Balance error: \(error.localizedDescription)")
        }
    }
}

private extension BalanceService {
    
    private var enableAutoCompoundStakedBalance: Bool { false }
    
    func fetchStakedBalance(for coin: Coin) async throws -> String {
        switch coin.chain {
        case .thorChain:
            // Handle TCY staked balance (includes both regular and auto-compound)
            if coin.ticker.caseInsensitiveCompare("TCY") == .orderedSame {
                let tcyStakedBalance = await thor.fetchTcyStakedAmount(address: coin.address)
                
                if enableAutoCompoundStakedBalance {
                    let tcyAutoCompoundBalance = await thor.fetchTcyAutoCompoundAmount(address: coin.address)
                    let totalStakedBalance = tcyStakedBalance + tcyAutoCompoundBalance
                    return totalStakedBalance.description
                }
                
                let totalStakedBalance = tcyStakedBalance
                return totalStakedBalance.description
                
            }
            
            // Handle RUNE bonded balance
            if coin.ticker.caseInsensitiveCompare("RUNE") == .orderedSame {
                let runeBondedBalance = await thor.fetchRuneBondedAmount(address: coin.address)
                return runeBondedBalance.description
            }
            
            // Handle merge account balances for non-native tokens
            if !coin.isNativeToken {
                let mergedAccounts = await thor.fetchMergeAccounts(address: coin.address)
                
                if let matchedAccount = mergedAccounts.first(where: {
                    $0.pool.mergeAsset.metadata.symbol.caseInsensitiveCompare(coin.ticker) == .orderedSame
                }) {
                    let amountInDecimal = matchedAccount.size.amount.toDecimal()
                    return amountInDecimal.description
                }
            }
            
            // Fallback return value
            return "0"
            
        default:
            // All other chains currently don't support staking
            return .zero
        }
    }
    
    func fetchBalance(for coin: Coin) async throws -> String {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            let blockChairData = try await utxo.fetchBlockchairData(coin: coin)
            
            // Calculate usable balance (excluding dust UTXOs)
            if let utxos = blockChairData.utxo {
                let dustThreshold = coin.coinType.getFixedDustThreshold()
                let usableUtxos = utxos.filter { ($0.value ?? 0) >= Int(dustThreshold) }
                let usableBalance = usableUtxos.reduce(0) { $0 + Int64($1.value ?? 0) }
                
                // Log the difference for debugging
                let totalBalance = blockChairData.address?.balance ?? 0
                let dustBalance = totalBalance - Int(usableBalance)
                
                if dustBalance > 0 {
                    print("💰 \(coin.ticker) Balance Analysis:")
                    print("  Total: \(totalBalance) sats (\(Double(totalBalance)/100_000_000) \(coin.ticker))")
                    print("  Usable: \(usableBalance) sats (\(Double(usableBalance)/100_000_000) \(coin.ticker))")
                    print("  Dust: \(dustBalance) sats (\(Double(dustBalance)/100_000_000) \(coin.ticker))")
                    print("  Dust UTXOs: \(utxos.count - usableUtxos.count) of \(utxos.count)")
                }
                
                // Return usable balance instead of total balance
                return usableBalance.description
            }
            
            // Fallback to total balance if no UTXO data available
            return blockChairData.address?.balance?.description ?? "0"
            
        case .cardano:
            return try await cardano.getBalance(coin: coin)
            
        case .thorChain:
            let thorBalances = try await thor.fetchBalances(coin.address)
            return thorBalances.balance(denom: Chain.thorChain.ticker.lowercased(), coin: coin)
            
        case .solana:
            return try await sol.getSolanaBalance(coin: coin)
            
        case .sui:
            return try await sui.getBalance(coin: coin)
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .polygonV2, .blast, .cronosChain, .zksync, .ethereumSepolia, .mantle:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            return try await service.getBalance(coin: coin)
            
        case .gaiaChain, .dydx, .kujira, .osmosis, .terra, .terraClassic, .noble, .akash:
            let cosmosService = try CosmosServiceFactory.getService(forChain: coin.chain)
            let balances = try await cosmosService.fetchBalances(coin: coin)
            
            // Determine the correct denom for each chain
            let denom: String
            switch coin.chain {
            case .terra, .terraClassic:
                denom = "uluna"
            default:
                denom = coin.chain.ticker.lowercased()
            }
            
            return balances.balance(denom: denom, coin: coin)
            
        case .mayaChain:
            let mayaBalance = try await maya.fetchBalances(coin.address)
            return mayaBalance.balance(denom: coin.ticker.lowercased())
            
        case .polkadot:
            return try await dot.getBalance(coin: coin)
            
        case .ton:
            if coin.isNativeToken {
                return try await ton.getBalance(coin)
            } else {
                return try await ton.getJettonBalance(coin)
            }
            
        case .ripple:
            return try await ripple.getBalance(coin)
            
        case .tron:
            return try await tron.getBalance(coin: coin)
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
