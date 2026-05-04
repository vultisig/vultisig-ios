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
    var onTransfer: (StakePosition) -> Void
    var emptyStateView: () -> EmptyStateView

    var showLoading: Bool {
        !viewModel.initialLoadingDone
    }

    var formattedStakePositions: [(position: StakePosition, fiatAmount: String)] {
        viewModel.stakePositions
            .map { position -> (position: StakePosition, fiatAmount: Decimal) in
                // Use the position's `CoinMeta` for the rate lookup so zero-amount placeholders
                // (and any position whose `Coin` row isn't yet in `vault.coins` — e.g. when the
                // background `CoinService.addToChain` call hasn't completed or silently failed)
                // still render. Filtering by `vault.coins.first(...)` here was the reason
                // freshly-enabled positions disappeared after a refresh.
                let fiatAmount = RateProvider.shared.fiatBalance(value: position.amount, coin: position.coin)
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
                        onWithdraw: { onWithdraw(position) },
                        onTransfer: { onTransfer(position) }
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
        onTransfer: { _ in },
        emptyStateView: { EmptyView() }
    )
    .environmentObject(HomeViewModel())
}
