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
    // Value-type projection the wallet chain list renders off. Rebuilt in
    // lockstep with `chains` so chain membership becomes the reactive source —
    // `@ObservedObject var vault` is inert for relationship/balance mutations
    // (Vault/Coin are @Model + ObservableObject with no @Published members),
    // so the list only repaints when a @Published on this view model changes.
    @Published private(set) var rows: [ChainRowModel] = []
    @Published var searchText: String = ""
    @Published var vaultBanners: [VaultBannerType] = []

    private let logic = VaultDetailLogic()
    private var updateBalanceTask: Task<Void, Never>?
    // Identity tracker for the vault `chains` was last sorted against. Used to
    // re-seed `chains` synchronously when `updateBalance(vault:)` is called
    // against a different vault than the cached list belongs to — the
    // vault-switch case. Without this, the `chains.isEmpty` guard below skips
    // the synchronous seed and the user sees the previous vault's chain list
    // until the async refresh lands (~250ms debounce + network round trip).
    private var chainsVaultPubKeyECDSA: String?

    private let bannerStore: PromoBannerDismissalStoring

    init(bannerStore: PromoBannerDismissalStoring = PromoBannerDismissalStore.shared) {
        self.bannerStore = bannerStore
    }

    func filteredChains(in vault: Vault) -> [Chain] {
        logic.filteredChains(searchText: searchText, chains: chains, vault: vault)
    }

    // `vault` is accepted for call-site parity with `filteredChains(in:)` but
    // is unused: rows carry their own `chain` and precomputed `nativeTicker`,
    // so search matches without a per-row lookup through the vault.
    func filteredRows(in _: Vault) -> [ChainRowModel] {
        logic.filteredRows(searchText: searchText, rows: rows)
    }

    var availableActions: [CoinAction] {
        [.swap, .send, .buy, .receive].filtered
    }

    func updateBalance(vault: Vault) {
        // Seed `chains`/`rows` synchronously when the cached list is empty
        // (first call), when it was sorted against a different vault than the
        // one we're now refreshing (vault-switch case), OR when chain
        // membership changed (a chain was added/removed on the same vault).
        // A same-vault, same-membership refresh (post-swap balance cascade)
        // still skips the seed, leaving the existing order until the async
        // sort below replaces it — that preserves the fix for the
        // "stale-then-fresh" double reorder. The membership check makes a
        // freshly added/removed chain appear in the same runloop as the save
        // instead of waiting on the network-gated async tail. Token
        // auto-discovery adds non-native coins to existing chains, so the
        // chain set is unchanged and the list does not reshuffle.
        let membershipChanged = Set(vault.chainsWithCoins) != Set(chains)
        if chains.isEmpty || chainsVaultPubKeyECDSA != vault.pubKeyECDSA || membershipChanged {
            chains = logic.sortedChains(vault: vault)
            rows = logic.chainRows(vault: vault)
            chainsVaultPubKeyECDSA = vault.pubKeyECDSA
        }

        updateBalanceTask?.cancel()
        updateBalanceTask = Task { [weak self] in
            // Leading debounce — `refresh()` fires from ~6 entry points
            // (onLoad, vault switch, shouldRefresh, vault.coins count change,
            // throttledOnAppear, pull-to-refresh). Post-swap they can stack
            // 2–3 deep within a second; without this sleep each call kicks
            // off a full price + per-coin balance refresh and the resulting
            // reorders are visible as flicker.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let updated = await self.logic.updateBalance(vault: vault)
            if !Task.isCancelled {
                await MainActor.run {
                    self.chains = updated
                    self.rows = self.logic.chainRows(vault: vault)
                    self.chainsVaultPubKeyECDSA = vault.pubKeyECDSA
                }
            }
        }
    }

    func groupChains(vault: Vault) {
        chains = logic.sortedChains(vault: vault)
        rows = logic.chainRows(vault: vault)
        chainsVaultPubKeyECDSA = vault.pubKeyECDSA
    }

    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        let currentChains = chains
        Task { @MainActor in
            selectedChain = await logic.preferredChain(chains: currentChains, viewModel: viewModel)
        }
    }

    func setupBanners(for vault: Vault) {
        vaultBanners = logic.setupBanners(for: vault, store: bannerStore)
    }

    @MainActor
    func removeBanner(for vault: Vault, banner: VaultBannerType) {
        bannerStore.dismiss(banner, now: Date())
        setupBanners(for: vault)
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

    func filteredRows(searchText: String, rows: [ChainRowModel]) -> [ChainRowModel] {
        guard !searchText.isEmpty else {
            return rows
        }
        return rows.filter { row in
            let nameMatches = row.chain.name.localizedCaseInsensitiveContains(searchText)
            let tickerMatches = row.nativeTicker.localizedCaseInsensitiveContains(searchText)
            return nameMatches || tickerMatches
        }
    }

    /// Builds the row projection in a single pass over `vault.coins`, grouping
    /// coins by chain once instead of calling `vault.coins(for:)` per row. The
    /// ordering matches `sortedChains(vault:)` exactly (fiat balance desc,
    /// tie-broken by `chain.index`).
    func chainRows(vault: Vault) -> [ChainRowModel] {
        let coinsByChain = Dictionary(grouping: vault.coins, by: { $0.chain })
        let ordered = sortedChains(
            chains: Array(coinsByChain.keys),
            value: { (coinsByChain[$0] ?? []).totalBalanceInFiatDecimal }
        )
        return ordered.map { chain in
            let coins = coinsByChain[chain] ?? []
            let native = coins.first(where: { $0.isNativeToken })
            return ChainRowModel(
                chain: chain,
                nativeTicker: native?.ticker ?? "",
                address: native?.address ?? coins.first?.address ?? "",
                fiatBalance: coins.totalBalanceInFiatDecimal.formatToFiat(includeCurrencySymbol: true),
                cryptoBalance: native?.balanceStringWithTicker ?? "",
                assetCount: coins.count
            )
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

    func setupBanners(
        for vault: Vault,
        store: PromoBannerDismissalStoring,
        now: Date = Date()
    ) -> [VaultBannerType] {
        return VaultBannerType.allCases
            .filter { banner in
                guard !store.isDismissed(banner, now: now) else { return false }

                switch banner {
                case .backupVault:
                    return !vault.isBackedUp
                case .upgradeVault:
                    return vault.libType == .GG20
                case .buyVult, .followVultisig:
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
