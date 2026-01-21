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

    init(coin: Coin) {
        self.coin = coin
    }

    func setup() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: coin.chain).filtered
        }
    }
}
