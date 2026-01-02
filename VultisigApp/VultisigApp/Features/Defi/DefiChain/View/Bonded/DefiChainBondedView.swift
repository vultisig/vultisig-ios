//
//  DefiChainBondedView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainBondedView<EmptyStateView: View>: View {
    @ObservedObject var viewModel: DefiChainBondViewModel

    let coin: Coin
    var onBond: (BondNode?) -> Void
    var onUnbond: (BondNode) -> Void
    var emptyStateView: () -> EmptyStateView
        
    var body: some View {
        LazyVStack(spacing: 14) {
            if !viewModel.hasBondPositions {
                emptyStateView()
            } else {
                bondedSection
                activeNodesSection
                availableNodesSection
            }
        }
    }

    var bondedSection: some View {
        ContainerView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    AsyncImageView(
                        logo: coin.logo,
                        size: CGSize(width: 40, height: 40),
                        ticker: coin.ticker,
                        tokenChainLogo: nil
                    )
                    
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(String(format: "bondedCoin".localized, coin.ticker))
                            .font(Theme.fonts.footnote)
                            .foregroundStyle(Theme.colors.textTertiary)
                        
                        HiddenBalanceText(viewModel.totalBondedBalance)
                            .font(Theme.fonts.priceTitle1)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.interpolatingSpring, value: viewModel.totalBondedBalance)
                        
                        HiddenBalanceText(viewModel.totalBondedBalanceFiat)
                            .font(Theme.fonts.priceCaption)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                    Spacer()
                }
                
                Separator(color: Theme.colors.border, opacity: 1)
                PrimaryButton(title: "bondToNode") {
                    onBond(nil)
                }
            }
        }
    }
    
    var availableNodesSection: some View {
        DefiChainAvailableNodesView(
            availableNodes: viewModel.availableNodes,
            onBond: onBond
        )
    }
    
    var activeNodesSection: some View {
        DefiChainActiveNodesView(
            coin: coin,
            activeNodes: viewModel.activeBondedNodes,
            canUnbond: viewModel.canUnbond,
            onBond: onBond,
            onUnbond: onUnbond
        )
    }
}

#Preview {
    DefiChainBondedView(
        viewModel: DefiChainBondViewModel(vault: .example, chain: .thorChain),
        coin: Coin.example,
        onBond: { _ in },
        onUnbond: { _ in },
        emptyStateView: { EmptyView() }
    )
}
