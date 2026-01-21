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

    var formattedStakePositions: [(position: StakePosition, fiatAmount: String)] {
        viewModel.stakePositions.compactMap { position -> (position: StakePosition, fiatAmount: Decimal)? in
            guard let coin = viewModel.vault.coins.first(where: { $0.toCoinMeta() == position.coin }) else {
                return nil
            }

            let fiatAmount = coin.fiat(decimal: position.amount)
            return (position, fiatAmount)
        }
        .sorted { $0.fiatAmount > $1.fiatAmount }
        .map { ($0.position, $0.fiatAmount.formatToFiat(includeCurrencySymbol: true))}
    }

    var body: some View {
        LazyVStack(spacing: 14) {
            if showLoading {
                ForEach(0..<2, id: \.self) { _ in
                    DefiChainStakedPositionSkeletonView()
                }
            } else if viewModel.hasStakePositions {
                ForEach(formattedStakePositions, id: \.position) { position, fiatAmount in
                    DefiChainStakedPositionView(
                        position: position,
                        fiatAmount: fiatAmount,
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
