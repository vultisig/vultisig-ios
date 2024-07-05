//
//  TokenSelectionViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import Foundation
import OSLog
import WalletCore

@MainActor
class CoinSelectionViewModel: ObservableObject {
    @Published var groupedAssets: [String: [CoinMeta]] = [:]
    @Published var selection = Set<CoinMeta>()
    
    let actionResolver = CoinActionResolver()
    let balanceService = BalanceService.shared
    let priceService = CryptoPriceService.shared
    
    private let logger = Logger(subsystem: "assets-list", category: "view")
    
    func loadData(coin: Coin) async {
        await balanceService.updateBalance(for: coin)
    }
    
    func setData(for vault: Vault) {
        groupAssets()
        checkSelected(for: vault)
    }
    
    func hasTokens(chain: Chain) -> Bool {
        guard let coins = groupedAssets[chain.name] else { return false }
        return coins.count > 1
    }
    
    private func checkSelected(for vault: Vault) {
        selection = Set(vault.coins.map{$0.toCoinMeta()})
    }
    
    private func groupAssets() {
        groupedAssets = [:]
        groupedAssets = Dictionary(grouping: TokensStore.TokenSelectionAssets.sorted(by: { first, second in
            if first.isNativeToken {
                return true
            }
            return false
        })) { $0.chain.name }
    }
    
    func handleSelection(isSelected: Bool, asset: CoinMeta) {
        if isSelected {
            if !selection.contains(where: { $0.chain == asset.chain && $0.ticker == asset.ticker }) {
                selection.insert(asset)
            }
        } else {
            if let remove = selection.first(where: { $0.chain == asset.chain && $0.ticker == asset.ticker }) {
                selection.remove(remove)
            }
        }
    }
    
    public func saveAssets(for vault: Vault) async {
        await VaultService.saveAssets(for: vault, selection: selection)
    }
    
}
