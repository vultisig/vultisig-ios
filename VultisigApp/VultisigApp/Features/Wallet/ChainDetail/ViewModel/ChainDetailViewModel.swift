//
//  ChainDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

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
    @Published var availableBandwidth: Int64 = 0
    @Published var totalBandwidth: Int64 = 0
    @Published var availableEnergy: Int64 = 0
    @Published var totalEnergy: Int64 = 0
    @Published var isLoadingResources: Bool = false

    var isTron: Bool { nativeCoin.chain == .tron }

    init(vault: Vault, nativeCoin: Coin) {
        self.vault = vault
        self.nativeCoin = nativeCoin
    }

    func refresh() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: nativeCoin.chain).filtered
        }
    }

    func loadTronResources() {
        guard isTron else { return }

        Task { @MainActor in
            isLoadingResources = true
        }

        Task {
            defer {
                Task { @MainActor in
                    isLoadingResources = false
                }
            }

            do {
                let resource = try await TronService.shared.getAccountResource(address: nativeCoin.address)
                await MainActor.run {
                    availableBandwidth = resource.calculateAvailableBandwidth()
                    totalBandwidth = resource.freeNetLimit + resource.NetLimit
                    availableEnergy = resource.EnergyLimit - resource.EnergyUsed
                    totalEnergy = resource.EnergyLimit
                }
            } catch {
                // Silently handle errors — loading indicator is cleared by defer
            }
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
