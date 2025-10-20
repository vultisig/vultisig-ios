//
//  DefiTHORChainActiveNodeView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainActiveNodeView: View {
    let coin: Coin
    let activeNode: ActiveBondedNode
    
    var onUnbond: (BondNode) -> Void
    var onBond: (BondNode) -> Void
    
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yy"
        return formatter
    }()
    
    var formattedChurnDate: String {
        CustomDateFormatter.formatMontDayYear(activeNode.nextChurn)
    }
    
    var unbondDisabled: Bool { activeNode.node.state != .churnedOut }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(format: "nodeAddress".localized, activeNode.node.address.truncatedAddress))
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)
                Spacer()
                BondNodeStateView(state: activeNode.node.state)
            }
            
            HiddenBalanceText(String(format: "bondedXCoin".localized, coin.formatWithTicker(value: activeNode.amount)))
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            
            HStack(spacing: 4) {
                Icon(named: "percent", size: 16)
                Text("apy".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
                Spacer()
                
                Text(activeNode.apy.formatted(.percent))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
            
            Separator(color: Theme.colors.border, opacity: 1)
            
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    nextChurnView
                        .frame(maxWidth: .infinity, alignment: .leading)
                    nextAwardView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                bondButtonsView
                Text("waitChurnedOutNode".localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textLight)
                    .showIf(unbondDisabled)
            }
        }
    }
    
    var nextChurnView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Icon(named: "calendar-days", color: Theme.colors.textExtraLight, size: 16)
                Text("nextChurn".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
            }
            Text(formattedChurnDate)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textLight)
        }
    }
    
    var nextAwardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Icon(named: "trophy", color: Theme.colors.textExtraLight, size: 16)
                Text("nextAward".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
            }
            HiddenBalanceText(coin.formatWithTicker(value: activeNode.nextReward))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textLight)
        }
    }
    
    var bondButtonsView: some View {
        HStack(alignment: .top, spacing: 16) {
            DefiButton(title: "unbond".localized, icon: "broken-chain-3", type: .secondary) {
                onUnbond(activeNode.node)
            }.disabled(unbondDisabled)
            DefiButton(title: "bond".localized, icon: "chain-link-3") {
                onBond(activeNode.node)
            }
        }
    }
}

#Preview {
    VStack {
        DefiTHORChainActiveNodeView(
            coin: .example,
            activeNode: .init(
                node: .init(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
                amount: 500,
                apy: 0.1,
                nextReward: 200,
                nextChurn: Date().timeIntervalSince1970 + 300
            ),
            onUnbond: { _ in },
            onBond: { _ in }
        )
        
        DefiTHORChainActiveNodeView(
            coin: .example,
            activeNode: .init(
                node: .init(address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .churnedOut),
                amount: 500,
                apy: 0.1,
                nextReward: 200,
                nextChurn: Date().timeIntervalSince1970 + 300
            ),
            onUnbond: { _ in },
            onBond: { _ in }
        )
    }
    .environmentObject(HomeViewModel())
}
