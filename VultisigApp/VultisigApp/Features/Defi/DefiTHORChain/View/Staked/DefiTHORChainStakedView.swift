//
//  DefiTHORChainStakedView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainStakedView<EmptyStateView: View>: View {
    @ObservedObject var viewModel: DefiTHORChainStakeViewModel
    var onStake: (StakePosition) -> Void
    var onUnstake: (StakePosition) -> Void
    var onWithdraw: (StakePosition) -> Void
    var emptyStateView: () -> EmptyStateView
    
    var body: some View {
        LazyVStack(spacing: 14) {
            if viewModel.hasStakePositions {
                ForEach(viewModel.stakePositions) { position in
                    DefiTHORChainStakedPositionView(
                        position: position,
                        onStake: { onStake(position) },
                        onUnstake: { onUnstake(position) },
                        onWithdraw: { onWithdraw(position) }
                    )
                }
            } else {
                emptyStateView()
            }
        }
    }
}

#Preview {
    DefiTHORChainStakedView(
        viewModel: DefiTHORChainStakeViewModel(vault: .example),
        onStake: { _ in },
        onUnstake: { _ in },
        onWithdraw: { _ in },
        emptyStateView: { EmptyView() }
    )
    .environmentObject(HomeViewModel())
}
