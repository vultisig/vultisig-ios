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
        viewModel.lpPositions.compactMap { position -> (position: LPPosition, fiatAmount: Decimal)? in
            guard let coin = vault.coins.first(where: { $0.toCoinMeta() == position.coin1 }) else {
                return nil
            }

            let fiatAmount = coin.fiat(decimal: position.coin1Amount)
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
