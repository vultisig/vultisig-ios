//
//  DefiChainStakedView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainStakedView<EmptyStateView: View>: View {
    @ObservedObject var viewModel: DefiChainStakeViewModel
    var onStake: (StakePosition) -> Void
    var onUnstake: (StakePosition) -> Void
    var onWithdraw: (StakePosition) -> Void
    var emptyStateView: () -> EmptyStateView
    
    var showLoading: Bool {
        !viewModel.initialLoadingDone
    }
    
    var body: some View {
        LazyVStack(spacing: 14) {
            if showLoading {
                ForEach(0..<2, id: \.self) { _ in
                    DefiChainStakedPositionSkeletonView()
                }
            } else if viewModel.hasStakePositions {
                ForEach(viewModel.stakePositions) { position in
                    DefiChainStakedPositionView(
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
    DefiChainStakedView(
        viewModel: DefiChainStakeViewModel(vault: .example, chain: .thorChain),
        onStake: { _ in },
        onUnstake: { _ in },
        onWithdraw: { _ in },
        emptyStateView: { EmptyView() }
    )
    .environmentObject(HomeViewModel())
}
