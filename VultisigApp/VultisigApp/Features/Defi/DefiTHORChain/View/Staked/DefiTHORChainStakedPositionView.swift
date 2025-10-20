//
//  DefiTHORChainStakedPositionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import SwiftUI

struct DefiTHORChainStakedPositionView: View {
    let position: StakePosition
    var onStake: () -> Void
    var onUnstake: () -> Void
    var onWithdraw: () -> Void
    
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yy"
        return formatter
    }()
    
    var stakedAmount: String {
        AmountFormatter.formatCryptoAmount(value: position.amount, coin: position.coin)
    }
    
    var title: String {
        switch position.type {
        case .stake:
            String(format: "stakedCoin".localized, position.coin.ticker)
        case .compound:
            String(format: "compoundedCoin".localized, position.coin.ticker)
        }
    }
    
    var formattedPayoutDate: String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(position.nextPayout)))
    }
    
    var unstakeDisabled: Bool { position.amount.isZero }
    var canWithdraw: Bool { position.rewards > 0 }
    
    var body: some View {
        ContainerView {
            VStack(spacing: 16) {
                header
                Separator(color: Theme.colors.borderLight, opacity: 1)
                rewardsSection
                Separator(color: Theme.colors.border, opacity: 1)
                stakeButtonsView
            }
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: position.coin.logo,
                size: CGSize(width: 40, height: 40),
                ticker: position.coin.ticker,
                tokenChainLogo: nil
            )
            
            VStack(alignment: .leading, spacing: .zero) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
                
                HiddenBalanceText(stakedAmount)
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.interpolatingSpring, value: stakedAmount)
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    var rewardsSection: some View {
        HStack(spacing: 4) {
            Icon(named: "percent", size: 16)
            Text("apr".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textExtraLight)
            Spacer()
            
            Text(position.apr.formatted(.percent))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.alertSuccess)
        }
                
        HStack(alignment: .top, spacing: 16) {
            nextPayoutView
                .frame(maxWidth: .infinity, alignment: .leading)
            estimatedRewardView
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var nextPayoutView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Icon(named: "calendar-days", color: Theme.colors.textExtraLight, size: 16)
                Text("nextPayout".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
            }
            Text(formattedPayoutDate)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textLight)
        }
    }
    
    var estimatedRewardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Icon(named: "trophy", color: Theme.colors.textExtraLight, size: 16)
                Text("estimatedReward".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
            }
            HiddenBalanceText(AmountFormatter.formatCryptoAmount(value: position.estimatedReward, coin: position.coin))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textLight)
        }
    }
    
    @ViewBuilder
    var stakeButtonsView: some View {
        if canWithdraw {
            withdrawButtonsView
        } else {
            defaultButtonsView
        }
    }
    
    var defaultButtonsView: some View {
        HStack(alignment: .top, spacing: 16) {
            DefiButton(title: "unstake".localized, icon: "minus-circle", type: .secondary) {
                onUnstake()
            }.disabled(unstakeDisabled)
            DefiButton(title: "stake".localized, icon: "plus-circle") {
                onStake()
            }
        }
    }
    
    var withdrawTitle: String {
        let amount = AmountFormatter.formatCryptoAmount(value: position.rewards, coin: position.rewardCoin)
        return String(format: "withdrawAmount".localized, amount)
    }
    
    var withdrawButtonsView: some View {
        HStack(spacing: 8) {
            PrimaryButton(title: withdrawTitle, action: onWithdraw)
            
            Menu {
                Section("actions".localized) {
                    Button(role: .destructive) {
                        onUnstake()
                    } label: {
                        Label(String(format: "unstakeCoin".localized, position.coin.ticker), systemImage: "minus")
                    }
                    .disabled(unstakeDisabled)
                    
                    Button {
                        onStake()
                    } label: {
                        Label(String(format: "stakeCoin".localized, position.coin.ticker), systemImage: "plus")
                    }
                }
            } label: {
                IconButton(icon: "dot-grid-1x3-vertical", type: .secondary, size: .small, action: {})
            }
        }
    }
}

#Preview {
    VStack {
        DefiTHORChainStakedPositionView(
            position: StakePosition(
                coin: .example,
                type: .stake,
                amount: 500,
                apr: 0.1,
                estimatedReward: 200,
                nextPayout: Date().timeIntervalSince1970 + 300,
                rewards: 0,
                rewardCoin: .example
            ),
            onStake: {},
            onUnstake: {},
            onWithdraw: {}
        )
        
        DefiTHORChainStakedPositionView(
            position: StakePosition(
                coin: .example,
                type: .stake,
                amount: 500,
                apr: 0.1,
                estimatedReward: 200,
                nextPayout: Date().timeIntervalSince1970 + 300,
                rewards: 300,
                rewardCoin: .example
            ),
            onStake: {},
            onUnstake: {},
            onWithdraw: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
}
