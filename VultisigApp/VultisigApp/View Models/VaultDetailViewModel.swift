//
//  VaultDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI

class VaultDetailViewModel: ObservableObject {
    @Published var selectedGroup: GroupedChain? = nil
    @Published var groups = [GroupedChain]()
    @Published var searchText: String = ""
    @Published var vaultBanners: [VaultBannerType] = []
    
    @AppStorage("appClosedBanners") private var appClosedBanners: [String] = []
    
    var filteredGroups: [GroupedChain] {
        guard !searchText.isEmpty else {
            return groups
        }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.nativeCoin.ticker.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let balanceService = BalanceService.shared
    private var updateBalanceTask: Task<Void, Never>?
    
    var availableActions: [CoinAction] {
        [.send, .buy, .swap, .receive].filtered
    }
    
    func updateBalance(vault: Vault) {
        print("Updating balance for vault: \(vault.name)")
        updateBalanceTask?.cancel()
        updateBalanceTask = Task.detached {
            await self.balanceService.updateBalances(vault: vault)
            if !Task.isCancelled {
                await self.categorizeCoins(vault: vault)
            }
        }
    }
    
    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        Task {@MainActor in
            selectedGroup = await getGroup(viewModel)
        }
    }
    
    @MainActor func categorizeCoins(vault: Vault) {
        var groups = [GroupedChain]()

        for coin in vault.coins {
            addCoin(coin, groups: &groups)
        }

        groups.sort {
            if $0.totalBalanceInFiatDecimal == $1.totalBalanceInFiatDecimal {
                return $0.chain.index < $1.chain.index
            }
            return $0.totalBalanceInFiatDecimal > $1.totalBalanceInFiatDecimal
        }
        self.groups = groups
    }
    
    func setupBanners(for vault: Vault) {
        vaultBanners = VaultBannerType.allCases
            .filter { banner in
                if banner.isAppBanner && appClosedBanners.contains(banner.rawValue) {
                    return false
                } else if vault.closedBanners.contains(banner.rawValue) {
                    return false
                }
                
                switch banner {
                case .backupVault:
                    return !vault.isBackedUp
                case .upgradeVault:
                    return vault.libType == .GG20
                case .followVultisig:
                    return true
                }
            }
    }
    
    @MainActor
    func removeBanner(for vault: Vault, banner: VaultBannerType) {
        guard !banner.isAppBanner else {
            appClosedBanners.append(banner.rawValue)
            setupBanners(for: vault)
            return
        }
        
        vault.closedBanners = Array(Set(vault.closedBanners + [banner.rawValue]))
        do {
            try Storage.shared.save()
            setupBanners(for: vault)
        } catch {
            print("Error while saving closedBanners for vault", error.localizedDescription)
        }
    }
}

private extension VaultDetailViewModel {
    func getGroup(_ viewModel: CoinSelectionViewModel) async -> GroupedChain? {
        for group in groups {
            let actions = await viewModel.actionResolver.resolveActions(for: group.chain)
            
            for action in actions {
                if action == .swap {
                    return group
                }
            }
        }
        return groups.first
    }
    
    func addCoin(_ coin: Coin, groups: inout [GroupedChain]) {
        let group = groups.first {
            group in group.address == coin.address && group.chain == coin.chain
        }
        
        guard let group else {
            let chain = GroupedChain(
                chain: coin.chain,
                address: coin.address,
                logo: coin.chain.logo,
                count: 1,
                coins: [coin]
            )
            
            groups.append(chain)
            return
        }
        
        // Check if coin already exists in group to prevent duplicates
        if !group.coins.contains(where: { $0.id == coin.id }) {
            group.coins.append(coin)
            group.count += 1
        }
        if coin.isNativeToken {
            group.logo = coin.chain.logo
        }
        return
    }
}
