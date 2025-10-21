//
//  DefiTHORChainBondedView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainBondedView: View {
    @ObservedObject var viewModel: DefiTHORChainBondViewModel

    let coin: Coin
    var onBond: (BondNode?) -> Void
    var onUnbond: (BondNode) -> Void

    var showBondButton: Bool {
        coin.stakedBalanceDecimal > 0
    }
    
    var bondedBalance: String {
        coin.formatWithTicker(value: coin.stakedBalanceDecimal)
    }
        
    var body: some View {
        LazyVStack(spacing: 14) {
            bondedSection
            activeNodesSection
            availableNodesSection
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
                        Text("bondedRune".localized)
                            .font(Theme.fonts.footnote)
                            .foregroundStyle(Theme.colors.textExtraLight)
                        
                        HiddenBalanceText(bondedBalance)
                            .font(Theme.fonts.priceTitle1)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.interpolatingSpring, value: bondedBalance)
                    }
                    Spacer()
                }
                
                Group {
                    Separator(color: Theme.colors.border, opacity: 1)
                    PrimaryButton(title: "bondToNode") {
                        onBond(nil)
                    }
                }
                .transition(.verticalGrowAndFade)
                .showIf(showBondButton)
            }
        }
    }
    
    var availableNodesSection: some View {
        DefiTHORChainAvailableNodesView(
            availableNodes: viewModel.availableNodes,
            onBond: onBond
        )
    }
    
    var activeNodesSection: some View {
        DefiTHORChainActiveNodesView(
            coin: coin,
            activeNodes: viewModel.activeBondedNodes,
            onBond: onBond,
            onUnbond: onUnbond
        )
    }
}

#Preview {
    DefiTHORChainBondedView(
        viewModel: DefiTHORChainBondViewModel(vault: .example),
        coin: Coin.example,
        onBond: { _ in },
        onUnbond: { _ in }
    )
}
