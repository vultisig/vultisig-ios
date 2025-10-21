//
//  DefiTHORChainStakedView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainStakedView: View {
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
    var onStake: (StakePosition) -> Void
    var onUnstake: (StakePosition) -> Void
    var onWithdraw: (StakePosition) -> Void
    
    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(stakePositions) { position in
                DefiTHORChainStakedPositionView(
                    position: position,
                    onStake: { onStake(position) },
                    onUnstake: { onUnstake(position) },
                    onWithdraw: { onWithdraw(position) }
                )
            }
        }
    }
}

#Preview {
    DefiTHORChainStakedView(
        onStake: { _ in },
        onUnstake: { _ in },
        onWithdraw: { _ in }
    )
    .environmentObject(HomeViewModel())
}
