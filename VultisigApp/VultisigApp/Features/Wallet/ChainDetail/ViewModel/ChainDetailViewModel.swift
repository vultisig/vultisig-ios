//
//  ChainDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import Combine
import Foundation

final class ChainDetailViewModel: ObservableObject {
    private let nativeCoin: Coin
    private let vault: Vault

    @Published var searchText: String = ""
    @Published var selectedTab: ChainDetailTab = .tokens
    /// Sorted token list for the current chain. Stored (not computed) and
    /// recomputed on a debounced `vault.objectWillChange` signal so a single
    /// balance refresh that mutates N coins doesn't trigger N filter+sort
    /// passes (#4337). Two non-native tokens with similar fiat values would
    /// otherwise swap order on every property publish and read as flicker.
    @Published private(set) var tokens: [Coin] = []

    var tabs: [SegmentedControlItem<ChainDetailTab>] = [
        SegmentedControlItem(value: .tokens, title: "tokens".localized)
    ]

    let actionResolver = CoinActionResolver()

    @Published var availableActions: [CoinAction] = []

    // Tron resources
    let tronLoader: TronResourcesLoader?
    var isTron: Bool { nativeCoin.chain == .tron }

    private var cancellables = Set<AnyCancellable>()

    init(vault: Vault, nativeCoin: Coin) {
        self.vault = vault
        self.nativeCoin = nativeCoin
        self.tronLoader = nativeCoin.chain == .tron ? TronResourcesLoader(address: nativeCoin.address) : nil
        self.tokens = Self.computeTokens(vault: vault, nativeCoin: nativeCoin)

        tronLoader?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Vault publishes once per `coin.rawBalance` write during a refresh —
        // 20+ times per cycle. Debounce so we sort once at the end.
        vault.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeTokens() }
            .store(in: &cancellables)
    }

    func refresh() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: nativeCoin.chain).filtered
        }
        recomputeTokens()
    }

    var filteredTokens: [Coin] {
        if searchText.isEmpty {
            return tokens
        } else {
            return tokens.filter {
                $0.ticker.lowercased().contains(searchText.lowercased())
            }
        }
    }

    private func recomputeTokens() {
        tokens = Self.computeTokens(vault: vault, nativeCoin: nativeCoin)
    }

    private static func computeTokens(vault: Vault, nativeCoin: Coin) -> [Coin] {
        vault.coins.filter { $0.chain == nativeCoin.chain }
            .filter { !$0.isDefiOnly }
            .uniqueBy { $0.uniqueId }
            .sorted {
                if $0.isNativeToken != $1.isNativeToken {
                    return $0.isNativeToken
                }
                return ($0.balanceInFiatDecimal) > ($1.balanceInFiatDecimal)
            }
    }
}
