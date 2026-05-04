//
//  DefiChainLPsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainLPsView<EmptyStateView: View>: View {
    @ObservedObject var vault: Vault
    @ObservedObject var viewModel: DefiChainLPsViewModel
    var onRemove: (LPPosition) -> Void
    var onAdd: (LPPosition) -> Void
    var emptyStateView: () -> EmptyStateView

    var showLoading: Bool {
        !viewModel.initialLoadingDone
    }

    var formattedLPs: [(position: LPPosition, fiatAmount: String)] {
        viewModel.lpPositions
            .map { position -> (position: LPPosition, fiatAmount: Decimal) in
                // Use `position.coin1` (CoinMeta) for the rate lookup rather than requiring a
                // matching `Coin` row in `vault.coins`. Otherwise zero-amount placeholders for
                // freshly-enabled pools disappear here even after the VM has them.
                let fiatAmount = RateProvider.shared.fiatBalance(value: position.coin1Amount, coin: position.coin1)
                return (position, fiatAmount)
            }
            .sorted { $0.fiatAmount > $1.fiatAmount }
            .map { ($0.position, $0.fiatAmount.formatToFiat(includeCurrencySymbol: true))}
    }

    var body: some View {
        LazyVStack(spacing: 14) {
            if showLoading {
                ForEach(0..<2, id: \.self) { _ in
                    DefiChainLPPositionSkeletonView()
                }
            } else if viewModel.hasLPPositions {
                ForEach(formattedLPs, id: \.position) { position, fiatAmount in
                    DefiChainLPPositionView(
                        vault: vault,
                        position: position,
                        fiatAmount: fiatAmount,
                        onRemove: { onRemove(position) },
                        onAdd: { onAdd(position) }
                    )
                }
            } else {
                emptyStateView()
            }
        }
    }
}

#Preview {
    DefiChainLPsView(
        vault: .example,
        viewModel: DefiChainLPsViewModel(vault: .example, chain: .thorChain),
        onRemove: { _ in },
        onAdd: { _ in },
        emptyStateView: { EmptyView() }
    )
}
