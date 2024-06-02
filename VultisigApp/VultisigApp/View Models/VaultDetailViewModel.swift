//
//  VaultDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI

@MainActor
class VaultDetailViewModel: ObservableObject {
    @Published var coinsGroupedByChains = [GroupedChain]()
    @Published var selectedGroup: GroupedChain? = nil
    private let semaphore = DispatchSemaphore(value: 1)
    
    let defaultChains = [Chain.bitcoin, Chain.ethereum, Chain.thorChain, Chain.solana]
    let balanceService = BalanceService.shared
    
    private var updateBalanceTask: Task<Void, Never>?
    
    func updateBalance() {
        updateBalanceTask?.cancel()
        updateBalanceTask = Task {
            let coins = coinsGroupedByChains.reduce([]) { $0 + $1.coins }
            await balanceService.updateBalances(coins: coins)
        }
    }
    
    func setOrder() {
        for index in 0..<coinsGroupedByChains.count {
            coinsGroupedByChains[index].setOrder(index)
        }
    }
    func setDefaultCoins(for vault: Vault){
        semaphore.wait()
        // add bitcoin when the vault doesn't have any coins in it
        if vault.coins.count == 0{
            print("set default coins for vault:\(vault.name)")
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
                    Task{
                        do{
                            try await Storage.shared.save(btc)
                            vault.coins.append(btc)
                        }catch{
                            print("fail to save coin: \(error)")
                        }
                    }
                case .failure(let error):
                    print("error: \(error)")
                }
                
            }
        }
        semaphore.signal()
    }
    
    func fetchCoins(for vault: Vault) {
        categorizeCoins(vault: vault)
    }
    
    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        Task {
            selectedGroup = await getGroup(viewModel)
        }
    }
    
    private func getGroup(_ viewModel: CoinSelectionViewModel) async -> GroupedChain? {
        for group in coinsGroupedByChains {
            let actions = await viewModel.actionResolver.resolveActions(for: group.chain)
            
            for action in actions {
                if action == .swap {
                    return group
                }
            }
        }
        return coinsGroupedByChains.first
    }
    
    private func categorizeCoins(vault: Vault) {
        coinsGroupedByChains = [GroupedChain]()
        
        for coin in vault.coins {
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
