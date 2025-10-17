//
//  DefiTHORChainBondedView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainBondedView: View {
    let coin: Coin
    var onBond: (BondNode?) -> Void
    var onUnbond: (BondNode) -> Void
    
    // TODO: - Fetch from RPC
    let availableNodes: [BondNode] = [
        BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
        BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szwasa", state: .churnedOut)
    ]
    
    // TODO: - Fetch from RPC
    let activeNodes: [ActiveBondedNode] = [
        ActiveBondedNode(
            node: BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
            amount: 300,
            apy: 0.3,
            nextReward: 15,
            nextChurn: Date().timeIntervalSince1970 + 3600
        ),
        ActiveBondedNode(
            node: BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szwasa", state: .churnedOut),
            amount: 500,
            apy: 0.22,
            nextReward: 20,
            nextChurn: Date().timeIntervalSince1970 + 3600
        )
    ]
    
    var showBondButton: Bool {
        coin.defiBalanceInFiatDecimal == 0
    }
    
    var body: some View {
        LazyVStack(spacing: 14) {
            bondedSection
            activeNodesSection
            availableNodesSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
                        
                        // TODO: - Replace with proper value after balance fetching is done
                        Text(coin.formatWithTicker(value: coin.stakedBalanceDecimal))
                            .font(Theme.fonts.priceTitle1)
                            .foregroundStyle(Theme.colors.textPrimary)
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
            availableNodes: availableNodes,
            onBond: onBond
        ) 
    }
    
    var activeNodesSection: some View {
        DefiTHORChainActiveNodesView(
            coin: coin,
            activeNodes: activeNodes,
            onBond: onBond,
            onUnbond: onUnbond
        )
    }
}

#Preview {
    DefiTHORChainBondedView(
        coin: Coin.example,
        onBond: { _ in },
        onUnbond: { _ in }
    )
}
