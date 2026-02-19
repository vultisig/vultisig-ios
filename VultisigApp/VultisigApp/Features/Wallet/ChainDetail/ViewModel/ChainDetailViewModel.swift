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

        tronLoader?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func refresh() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: nativeCoin.chain).filtered
        }
    }

    var tokens: [Coin] {
        return vault.coins.filter { $0.chain == nativeCoin.chain }
            .sorted {
                if $0.isNativeToken != $1.isNativeToken {
                    return $0.isNativeToken
                }
                return ($0.balanceInFiatDecimal) > ($1.balanceInFiatDecimal)
            }
    }

    var filteredTokens: [Coin] {
        if searchText.isEmpty {
            return tokens
        } else {
            let assets = tokens.filter {
                $0.ticker.lowercased().contains(searchText.lowercased())
            }

            return assets
        }
    }
}
