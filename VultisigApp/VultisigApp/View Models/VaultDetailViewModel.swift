//
//  VaultDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation

@MainActor
class VaultDetailViewModel: ObservableObject {
    @Published var coins = [Coin]()
    @Published var coinsGroupedByChains = [GroupedChain]()
    let defaultChains = [Chain.bitcoin,Chain.ethereum,Chain.thorChain,Chain.solana]
    @Published var totalBalanceInFiat: Decimal = 0
    
    func getTotalUpdatedBalance() async {
        var totalBalance: Decimal = 0
        
        await withTaskGroup(of: Decimal?.self) { group in
            for groupedChain in coinsGroupedByChains {
                for coin in groupedChain.coins {
                    group.addTask {
                        do {
                            return try await self.fetchBalanceWithRetry(for: coin, retries: 3, delay: 1.0)
                        } catch {
                            print("Error fetching balance for coin \(coin): \(error)")
                            return nil
                        }
                    }
                }
            }
            
            for await result in group {
                if let balance = result {
                    totalBalance += balance
                }
            }
        }
        
        self.totalBalanceInFiat = totalBalance
    }
    
    private func fetchBalanceWithRetry(for coin: Coin, retries: Int, delay: TimeInterval) async throws -> Decimal {
        var attempts = 0
        
        while attempts < retries {
            do {
                let (_, _, balanceInFiatDecimal) = try await BalanceService.shared.balance(for: coin)
                return balanceInFiatDecimal
            } catch {
                attempts += 1
                if attempts >= retries {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) // Sleep for the specified delay
            }
        }
        
        throw NSError(domain: "BalanceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch balance after \(retries) attempts"])
    }
    
    func fetchCoins(for vault: Vault) {
        // add bitcoin when the vault doesn't have any coins in it
        if vault.coins.count == 0 {
            for chain in defaultChains {
                var result: Result<Coin,Error>
                switch chain {
                case .bscChain:
                    result = EVMHelper(coinType: .smartChain).getCoin(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
                case .bitcoin:
                    result = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
                case .ethereum:
                    result = EVMHelper(coinType: .ethereum).getCoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                case .thorChain:
                    result = THORChainHelper.getRUNECoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                case .solana:
                    result = SolanaHelper.getSolana(hexPubKey: vault.pubKeyEdDSA, hexChainCode: vault.hexChainCode)
                default:
                    continue
                }
                
                switch result {
                case .success(let btc):
                    vault.coins.append(btc)
                case .failure(let error):
                    print("error: \(error)")
                }
                
            }
        }
        coins = vault.coins
        categorizeCoins()
    }
    
    private func categorizeCoins() {
        coinsGroupedByChains = [GroupedChain]()
        
        for coin in coins {
            addCoin(coin)
        }
        coinsGroupedByChains.sort { $0.name < $1.name }
    }
    
    private func addCoin(_ coin: Coin) {
        for group in coinsGroupedByChains {
            if group.address == coin.address && group.name == coin.chain.name {
                group.coins.append(coin)
                group.count+=1
                if coin.isNativeToken {
                    group.logo = coin.logo
                }
                return
            }
        }
        
        let chain = GroupedChain(
            chain: coin.chain,
            address: coin.address,
            logo: coin.logo,
            count: 1,
            coins: [coin]
        )
        coinsGroupedByChains.append(chain)
    }
}
