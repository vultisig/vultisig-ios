//
//  DefiTHORChainAvailableNodesView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainAvailableNodesView: View {
    let availableNodes: [BondNode]
    var onBond: (BondNode) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        ContainerView {
            ExpandableView(isExpanded: $isExpanded) {
                HStack {
                    Text("availableNodes".localized)
                        .foregroundStyle(Theme.colors.textLight)
                        .font(Theme.fonts.bodySMedium)
                    Spacer()
                    
                    Icon(named: "chevron-down", color: Theme.colors.textPrimary, size: 20)
                        .rotationEffect(.radians(isExpanded ? .pi : .zero))
                        .animation(.interpolatingSpring, value: isExpanded)
                }
            } content: {
                VStack(spacing: 16) {
                    ForEach(availableNodes) { node in
                        nodeView(for: node)
                        Separator(color: Theme.colors.border, opacity: 1)
                            .showIf(node != availableNodes.last)
                    }
                }
                .padding(.top, 16)
            }
        }
    }
    
    func nodeView(for node: BondNode) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(String(format: "nodeAddress".localized, node.address.truncatedAddress))
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)
                Spacer()
                BondNodeStateView(state: node.state)
            }
            
            DefiButton(title: "requestToBond".localized, icon: "arrow-up-right-1", type: .secondary) {
                onBond(node)
            }
        }
    }
}

#Preview {
    DefiTHORChainAvailableNodesView(
        availableNodes: [
            BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
            BondNode(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szwasa", state: .churnedOut)
        ],
        onBond: { _ in }
    )
}
