//
//  DefiChainAvailableNodesView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainAvailableNodesView: View {
    let availableNodes: [BondNode]
    var onBond: (BondNode) -> Void

    @State private var isExpanded = false

    var body: some View {
        ContainerView {
            ExpandableView(isExpanded: $isExpanded) {
                HStack {
                    Text("availableNodes".localized)
                        .foregroundStyle(Theme.colors.textSecondary)
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
        .showIf(!availableNodes.isEmpty)
        .onChange(of: availableNodes.count) { oldValue, newValue in
            if oldValue == 0, newValue > 0 {
                isExpanded = true
            }
        }
    }

    func nodeView(for node: BondNode) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(String(format: "nodeAddress".localized, node.address.truncatedAddress))
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                Spacer()
                BondNodeStateView(state: node.state)
            }

            DefiButton(title: "requestToBond".localized, icon: "arrow-up-right-1", type: .secondary) {
                onBond(node)
            }
            .disabled(!node.state.canBond)
        }
    }
}

#Preview {
    DefiChainAvailableNodesView(
        availableNodes: [
            BondNode(coin: .example, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
            BondNode(coin: .example, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szwasa", state: .ready),
            BondNode(coin: .example, address: "thor1disabled000000000000000000000000000000", state: .disabled)
        ],
        onBond: { _ in }
    )
}
