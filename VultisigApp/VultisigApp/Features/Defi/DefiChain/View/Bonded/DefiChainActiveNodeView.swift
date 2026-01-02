//
//  DefiChainActiveNodeView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainActiveNodeView: View {
    let coin: Coin
    let activeNode: BondPosition
    let canUnbond: Bool
    var onUnbond: (BondNode) -> Void
    var onBond: (BondNode) -> Void
    
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yy"
        return formatter
    }()
    
    var formattedChurnDate: String {
        guard let nextChurn = activeNode.nextChurn else {
            return "-"
        }
        return CustomDateFormatter.formatMonthDayYear(nextChurn)
    }
    
    var fiatAmount: String {
        coin.fiat(decimal: coin.valueWithDecimals(value: activeNode.amount)).formatToFiat()
    }
    
    var unbondDisabled: Bool { !activeNode.node.state.canUnbond || !canUnbond }
    var bondDisabled: Bool { !activeNode.node.state.canBond }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(format: "nodeAddress".localized, activeNode.node.address.truncatedAddress))
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                Spacer()
                BondNodeStateView(state: activeNode.node.state)
            }
            
            HStack(spacing: 4) {
                HiddenBalanceText(String(format: "bondedXCoin".localized, coin.formatWithTicker(value: activeNode.amount)))
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title3)
                Spacer()
                
                HiddenBalanceText(fiatAmount)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .lineLimit(1)
            
            HStack(spacing: 4) {
                Icon(named: "percent", size: 16)
                Text("apy".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                
                Text(activeNode.apy.formatted(.percent.precision(.fractionLength(2))))
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
                    .foregroundStyle(Theme.colors.textSecondary)
                    .showIf(unbondDisabled)
            }
        }
    }
    
    var nextChurnView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Icon(named: "calendar-days", color: Theme.colors.textTertiary, size: 16)
                Text("nextChurn".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Text(formattedChurnDate)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }
    
    var nextAwardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Icon(named: "trophy", color: Theme.colors.textTertiary, size: 16)
                Text("nextAward".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            HiddenBalanceText(coin.formatWithTicker(value: activeNode.nextReward))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }
    
    var bondButtonsView: some View {
        HStack(alignment: .top, spacing: 16) {
            DefiButton(title: "unbond".localized, icon: "broken-chain-3", type: .secondary) {
                onUnbond(activeNode.node)
            }
            .disabled(unbondDisabled)

            DefiButton(title: "bond".localized, icon: "chain-link-3") {
                onBond(activeNode.node)
            }
            .disabled(bondDisabled)
        }
    }
}

#Preview {
    VStack {
        DefiChainActiveNodeView(
            coin: .example,
            activeNode: .init(
                node: .init(coin: .example, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
                amount: 500,
                apy: 0.1,
                nextReward: 200,
                nextChurn: Date().addingTimeInterval(300),
                vault: .example
            ),
            canUnbond: false,
            onUnbond: { _ in },
            onBond: { _ in }
        )
        
        DefiChainActiveNodeView(
            coin: .example,
            activeNode: .init(
                node: .init(coin: .example, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .ready),
                amount: 500,
                apy: 0.1,
                nextReward: 200,
                nextChurn: Date().addingTimeInterval(400),
                vault: .example
            ),
            canUnbond: true,
            onUnbond: { _ in },
            onBond: { _ in }
        )
    }
    .environmentObject(HomeViewModel())
}
