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
    
    private let logic = VaultDetailLogic()
    private var updateBalanceTask: Task<Void, Never>?
    
    @AppStorage("appClosedBanners") private var appClosedBanners: [String] = []
    
    var filteredGroups: [GroupedChain] {
        return logic.filteredGroups(searchText: searchText, groups: groups)
    }

    var availableActions: [CoinAction] {
        [.swap,.send,.buy,.receive].filtered
    }
    
    func updateBalance(vault: Vault) {
        print("Updating balance for vault: \(vault.name)")
        updateBalanceTask?.cancel()
        updateBalanceTask = Task.detached { [weak self] in
            guard let self else { return }
            let updatedGroups = await self.logic.updateBalance(vault: vault)
            if !Task.isCancelled {
                await MainActor.run {
                    self.groups = updatedGroups
                }
            }
        }
    }
    
    func groupChains(vault: Vault) {
        self.groups = logic.groupChains(vault: vault)
    }
    
    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        Task {@MainActor in
            selectedGroup = await logic.getGroup(groups: groups, viewModel: viewModel)
        }
    }
    
    func setupBanners(for vault: Vault) {
        vaultBanners = logic.setupBanners(for: vault, appClosedBanners: appClosedBanners)
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
    
    func canShowChainSelection(vault: Vault) -> Bool {
        // Vault cannot change chains for KeyImport for now
        vault.libType != .KeyImport
    }
}

// MARK: - VaultDetailLogic

struct VaultDetailLogic {
    private let groupedChainListBuilder = GroupedChainListBuilder()
    private let balanceService = BalanceService.shared
    
    func filteredGroups(searchText: String, groups: [GroupedChain]) -> [GroupedChain] {
        guard !searchText.isEmpty else {
            return groups
        }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.nativeCoin.ticker.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func updateBalance(vault: Vault) async -> [GroupedChain] {
        await balanceService.updateBalances(vault: vault)
        return groupedChainListBuilder.groupChains(for: vault, sortedBy: \.totalBalanceInFiatDecimal)
    }
    
    func groupChains(vault: Vault) -> [GroupedChain] {
        return groupedChainListBuilder.groupChains(for: vault, sortedBy: \.totalBalanceInFiatDecimal)
    }
    
    func getGroup(groups: [GroupedChain], viewModel: CoinSelectionViewModel) async -> GroupedChain? {
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
    
    func setupBanners(for vault: Vault, appClosedBanners: [String]) -> [VaultBannerType] {
        return VaultBannerType.allCases
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
}

struct GroupedChainListBuilder {
    func groupChains<T: Comparable>(
        for vault: Vault,
        sortedBy keyPath: KeyPath<GroupedChain, T>,
        ascending: Bool = false,
        filterBy: (GroupedChain) -> Bool = { _ in true }
    ) -> [GroupedChain] {
        var groups = [GroupedChain]()

        for coin in vault.coins {
            addCoin(coin, groups: &groups)
        }

        groups.sort {
            let lhsValue = $0[keyPath: keyPath]
            let rhsValue = $1[keyPath: keyPath]
            
            if lhsValue == rhsValue {
                return $0.chain.index < $1.chain.index
            }
            return ascending ? lhsValue < rhsValue : lhsValue > rhsValue
        }
        
        return groups.filter(filterBy)
    }
    
    func addCoin(_ coin: Coin, groups: inout [GroupedChain]) {
        let group = groups.first { group in
            group.address == coin.address && group.chain == coin.chain
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
