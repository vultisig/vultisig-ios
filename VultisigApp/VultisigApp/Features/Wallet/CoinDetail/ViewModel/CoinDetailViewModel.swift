//
//  CoinDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import Combine
import Foundation

final class CoinDetailViewModel: ObservableObject {
    let coin: Coin

    @Published var availableActions: [CoinAction] = []
    private let actionResolver = CoinActionResolver()

    // Tron resources
    let tronLoader: TronResourcesLoader
    var isTron: Bool { coin.chain == .tron }

    private var cancellables = Set<AnyCancellable>()

    init(coin: Coin) {
        self.coin = coin
        self.tronLoader = TronResourcesLoader(address: coin.address)

        tronLoader.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func setup() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: coin.chain).filtered
        }
    }
}
