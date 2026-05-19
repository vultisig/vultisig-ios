//
//  VaultDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI

class VaultDetailViewModel: ObservableObject {
    @Published var selectedChain: Chain? = nil
    @Published var chains = [Chain]()
    @Published var searchText: String = ""
    @Published var vaultBanners: [VaultBannerType] = []

    private let logic = VaultDetailLogic()
    private var updateBalanceTask: Task<Void, Never>?

    @AppStorage("appClosedBanners") private var appClosedBanners: [String] = []

    func filteredChains(in vault: Vault) -> [Chain] {
        logic.filteredChains(searchText: searchText, chains: chains, vault: vault)
    }

    var availableActions: [CoinAction] {
        [.swap, .send, .buy, .receive].filtered
    }

    func updateBalance(vault: Vault) {
        // Seed `chains` synchronously on first call so the list isn't blank
        // through the debounce + fetch window. Subsequent refreshes leave the
        // existing order in place until the async sort below replaces it —
        // avoids the visible "stale-then-fresh" double reorder (#4337).
        if chains.isEmpty {
            chains = logic.sortedChains(vault: vault)
        }

        updateBalanceTask?.cancel()
        updateBalanceTask = Task { [weak self] in
            // Leading debounce — `refresh()` fires from ~6 entry points
            // (onLoad, vault switch, shouldRefresh, vault.coins count change,
            // throttledOnAppear, pull-to-refresh). Post-swap they can stack
            // 2–3 deep within a second; without this sleep each call kicks
            // off a full price + per-coin balance refresh and the resulting
            // reorders are visible as flicker (#4337).
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let updated = await self.logic.updateBalance(vault: vault)
            if !Task.isCancelled {
                await MainActor.run {
                    self.chains = updated
                }
            }
        }
    }

    func groupChains(vault: Vault) {
        chains = logic.sortedChains(vault: vault)
    }

    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        let currentChains = chains
        Task { @MainActor in
            selectedChain = await logic.preferredChain(chains: currentChains, viewModel: viewModel)
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
    private let balanceService = BalanceService.shared

    func filteredChains(searchText: String, chains: [Chain], vault: Vault) -> [Chain] {
        guard !searchText.isEmpty else {
            return chains
        }
        return chains.filter { chain in
            let nameMatches = chain.name.localizedCaseInsensitiveContains(searchText)
            let tickerMatches = vault.nativeCoin(for: chain)?.ticker
                .localizedCaseInsensitiveContains(searchText) ?? false
            return nameMatches || tickerMatches
        }
    }

    func updateBalance(vault: Vault) async -> [Chain] {
        await balanceService.updateBalances(vault: vault)
        return await MainActor.run { sortedChains(vault: vault) }
    }

    func sortedChains(vault: Vault) -> [Chain] {
        sortedChains(
            chains: vault.chainsWithCoins,
            value: { vault.coins(for: $0).totalBalanceInFiatDecimal }
        )
    }

    func preferredChain(chains: [Chain], viewModel: CoinSelectionViewModel) async -> Chain? {
        for chain in chains {
            let actions = await viewModel.actionResolver.resolveActions(for: chain)
            if actions.contains(.swap) {
                return chain
            }
        }
        return chains.first
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
                case .buyVult:
                    return true
                case .followVultisig:
                    return true
                }
            }
    }

    func sortedChains<T: Comparable>(
        chains: [Chain],
        ascending: Bool = false,
        value: (Chain) -> T
    ) -> [Chain] {
        chains.sorted { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            if lhsValue == rhsValue {
                return lhs.index < rhs.index
            }
            return ascending ? lhsValue < rhsValue : lhsValue > rhsValue
        }
    }
}
