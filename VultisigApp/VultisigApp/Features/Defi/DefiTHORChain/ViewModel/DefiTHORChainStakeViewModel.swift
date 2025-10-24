//
//  DefiTHORChainStakeViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

final class DefiTHORChainStakeViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    
    // TODO: - Fetch from RPC
    let stakePositions: [StakePosition] = [
        StakePosition(
            coin: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "TCY" }) ?? .example,
            type: .stake,
            amount: 500,
            apr: 0.1,
            estimatedReward: 200,
            nextPayout: Date().timeIntervalSince1970 + 300,
            rewards: 0,
            rewardCoin: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "RUNE" }) ?? .example
        ),
        StakePosition(
            coin: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "sTCY" }) ?? .example,
            type: .stake,
            amount: 500,
            apr: 0.1,
            estimatedReward: 200,
            nextPayout: Date().timeIntervalSince1970 + 300,
            rewards: 300,
            rewardCoin: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "RUNE" }) ?? .example
        )
    ]
    
    var hasStakePositions: Bool {
        !vaultStakePositions.isEmpty
    }
    
    var vaultStakePositions: [CoinMeta] {
        vault.defiPositions.first { $0.chain == .thorChain }?.staking ?? []
    }

    private let thorchainAPIService = THORChainAPIService()

    init(vault: Vault) {
        self.vault = vault
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
    }
}
