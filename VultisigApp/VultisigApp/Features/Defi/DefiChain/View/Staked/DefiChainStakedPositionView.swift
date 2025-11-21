//
//  DefiChainStakedPositionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import SwiftUI

struct DefiChainStakedPositionView: View {
    let position: StakePosition
    var onStake: () -> Void
    var onUnstake: () -> Void
    var onWithdraw: () -> Void
    
    var stakedAmount: String {
        AmountFormatter.formatCryptoAmount(value: position.amount, coin: position.coin)
    }
    
    var title: String {
        switch position.type {
        case .stake:
            String(format: "stakedCoin".localized, position.coin.ticker)
        case .compound:
            String(format: "compoundedCoin".localized, position.coin.ticker)
        case .index:
            position.coin.ticker
        }
    }

    var formattedPayoutDate: String? {
        guard let nextPayout = position.nextPayout else { return nil }
        return CustomDateFormatter.formatMonthDayYear(nextPayout)
    }

    var unstakeDisabled: Bool { position.amount.isZero }
    var canWithdraw: Bool {
        guard let rewards = position.rewards else { return false }
        return rewards > 0
    }

    var hasAPR: Bool { position.apr != nil }
    var hasEstimatedReward: Bool { position.estimatedReward != nil }
    var hasNextPayout: Bool { position.nextPayout != nil }
    
    var body: some View {
        ContainerView {
            VStack(spacing: 16) {
                header

                if hasAPR || hasNextPayout || hasEstimatedReward {
                    Separator(color: Theme.colors.borderLight, opacity: 1)
                    rewardsSection
                }

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
        if let apr = position.apr {
            HStack(spacing: 4) {
                Icon(named: "percent", size: 16)
                Text("apr".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
                Spacer()

                Text(apr.formatted(.percent.precision(.fractionLength(2))))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
        }

        if hasNextPayout || hasEstimatedReward {
            HStack(alignment: .top, spacing: 16) {
                if hasNextPayout {
                    nextPayoutView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if hasEstimatedReward {
                    estimatedRewardView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
            if let payoutDate = formattedPayoutDate {
                Text(payoutDate)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textLight)
            }
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
            if let estimatedReward = position.estimatedReward, let rewardCoin = position.rewardCoin {
                HiddenBalanceText(AmountFormatter.formatCryptoAmount(value: estimatedReward, coin: rewardCoin))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textLight)
            }
        }
    }
    
    @ViewBuilder
    var stakeButtonsView: some View {
        switch position.type {
        case .stake, .compound:
            VStack(spacing: 16) {
                PrimaryButton(title: withdrawTitle, action: onWithdraw)
                    .showIf(canWithdraw)
                defaultButtonsView
            }
        case .index:
            indexButtonsView
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

    var indexButtonsView: some View {
        HStack(alignment: .top, spacing: 16) {
            DefiButton(title: "redeem".localized, icon: "minus-circle", type: .secondary) {
                onUnstake() // Use onUnstake for redeem action
            }.disabled(unstakeDisabled)
            DefiButton(title: "mint".localized, icon: "plus-circle") {
                onStake() // Use onStake for mint action
            }
        }
    }
    
    var withdrawTitle: String {
        guard let rewards = position.rewards,
              let rewardCoin = position.rewardCoin else {
            return "withdraw".localized
        }
        let amount = AmountFormatter.formatCryptoAmount(value: rewards, coin: rewardCoin)
        return String(format: "withdrawAmount".localized, amount)
    }
}

#Preview {
    VStack {
        DefiChainStakedPositionView(
            position: StakePosition(
                coin: .example,
                type: .stake,
                amount: 500,
                apr: 0.1,
                estimatedReward: 200,
                nextPayout: Date().timeIntervalSince1970 + 300,
                rewards: 0,
                rewardCoin: .example,
                vault: .example
            ),
            onStake: {},
            onUnstake: {},
            onWithdraw: {}
        )
        
        DefiChainStakedPositionView(
            position: StakePosition(
                coin: .example,
                type: .stake,
                amount: 500,
                apr: 0.1,
                estimatedReward: 200,
                nextPayout: Date().timeIntervalSince1970 + 300,
                rewards: 300,
                rewardCoin: .example,
                vault: .example
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
