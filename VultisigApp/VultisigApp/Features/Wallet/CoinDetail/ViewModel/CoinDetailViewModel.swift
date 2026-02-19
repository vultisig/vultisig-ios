//
//  CoinDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import Foundation

final class CoinDetailViewModel: ObservableObject {
    let coin: Coin

    @Published var availableActions: [CoinAction] = []
    private let actionResolver = CoinActionResolver()

    // Tron resources
    @Published var availableBandwidth: Int64 = 0
    @Published var totalBandwidth: Int64 = 0
    @Published var availableEnergy: Int64 = 0
    @Published var totalEnergy: Int64 = 0
    @Published var isLoadingResources: Bool = false

    var isTron: Bool { coin.chain == .tron }

    init(coin: Coin) {
        self.coin = coin
    }

    func setup() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: coin.chain).filtered
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
                let resource = try await TronService.shared.getAccountResource(address: coin.address)
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
}
