//
//  DefiTHORChainActiveNodesView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainActiveNodesView: View {
    let coin: Coin
    let activeNodes: [ActiveBondedNode]
    var onBond: (BondNode) -> Void
    var onUnbond: (BondNode) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        ContainerView {
            ExpandableView(isExpanded: $isExpanded) {
                HStack {
                    Text("activeNodes".localized)
                        .foregroundStyle(Theme.colors.textLight)
                        .font(Theme.fonts.bodySMedium)
                    Spacer()
                    
                    Icon(named: "chevron-down", color: Theme.colors.textPrimary, size: 20)
                        .rotationEffect(.radians(isExpanded ? .pi : .zero))
                        .animation(.interpolatingSpring, value: isExpanded)
                }
            } content: {
                VStack(spacing: 16) {
                    ForEach(activeNodes) { node in
                        DefiTHORChainActiveNodeView(
                            coin: coin,
                            activeNode: node,
                            onUnbond: onUnbond,
                            onBond: onBond
                        )
                        Separator(color: Theme.colors.border, opacity: 1)
                            .showIf(node != activeNodes.last)
                    }
                }
                .padding(.top, 16)
            }
        }
        .transition(.verticalGrowAndFade)
        .showIf(activeNodes.count > 0)
        .onChange(of: activeNodes.count) { oldValue, newValue in
            if oldValue == 0, newValue > 0 {
                isExpanded = true
            }
        }
    }
}

#Preview {
    let asset = CoinMeta(chain: .thorChain, ticker: "RUNE", logo: "thorchain", decimals: 8, priceProviderId: "thorchain", contractAddress: "", isNativeToken: true)
    let coin = Coin(asset: asset, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", hexPublicKey: "HexPublicKeyExample")
    let activeNodes: [ActiveBondedNode] = [
        ActiveBondedNode(
            node: BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
            amount: 300,
            apy: 0.3,
            nextReward: 15,
            nextChurn: Date().addingTimeInterval(3600)
        ),
        ActiveBondedNode(
            node: BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szwasa", state: .ready),
            amount: 500,
            apy: 0.22,
            nextReward: 20,
            nextChurn: Date().addingTimeInterval(3600)
        )
    ]
    DefiTHORChainActiveNodesView(
        coin: coin,
        activeNodes: activeNodes,
        onBond: { _ in },
        onUnbond: { _ in }
    )
}
