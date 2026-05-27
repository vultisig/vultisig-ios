//
//  CosmosStakeDefiView.swift
//  VultisigApp
//
//  LUNA / LUNC stake segment of the DeFi chain tab. Renders an empty
//  state when no delegations exist, or a populated layout with:
//
//    - Hero banner with the chain name + fiat total + decorative rings
//    - "Total Staked %@" summary card with a "Delegate to New Validator" CTA
//    - Per-validator card with Unstake / Move (redelegate) / Stake actions
//    - 21-day unbonding lock footer + per-validator unbonding entries
//      when present
//
//  Action buttons hand off to the shared
//  `FunctionTransactionType.cosmos*` enum cases, which route through
//  `FunctionTransactionScreen` and into the per-flow Cosmos staking VMs.
//

import SwiftUI

struct CosmosStakeDefiView: View {
    let coin: Coin
    let totalFiat: String
    @ObservedObject var viewModel: CosmosStakeDefiViewModel
    var onDelegate: (Coin) -> Void
    var onUndelegate: (CosmosStakePositionRow) -> Void
    var onRedelegate: (CosmosStakePositionRow) -> Void
    var onClaim: ([CosmosStakePositionRow]) -> Void

    private static let apyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.positions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            } else if viewModel.positions.isEmpty {
                emptyState
            } else {
                populatedState
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Icon(named: "crypto", color: Theme.colors.primaryAccent4, size: 24)
            Text("noPositionsSelectedTitle".localized)
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("noPositionsSelectedSubtitle".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.colors.bgSurface1)
        )
    }

    @ViewBuilder
    private var populatedState: some View {
        VStack(spacing: 16) {
            totalStakedCard
            activeDelegationsCard
        }
    }

    @ViewBuilder
    private var totalStakedCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 48, height: 48),
                    ticker: coin.ticker,
                    tokenChainLogo: nil
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "cosmosStakingTotalStaked".localized, coin.ticker))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    HiddenBalanceText("\(formatAmount(viewModel.totalStaked)) \(coin.ticker)")
                        .font(Theme.fonts.priceTitle1)
                        .foregroundStyle(Theme.colors.textPrimary)
                    HiddenBalanceText(totalFiat)
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer(minLength: 8)
            }

            Separator(color: Theme.colors.borderLight, opacity: 1)

            PrimaryButton(
                title: "cosmosStakingDelegateNewValidator".localized
            ) {
                onDelegate(coin)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var activeDelegationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("cosmosStakingActiveDelegations".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer()
            }
            ForEach(Array(viewModel.positions.enumerated()), id: \.element.id) { index, position in
                positionRow(for: position)
                if index < viewModel.positions.count - 1 {
                    Separator(color: Theme.colors.borderLight, opacity: 1)
                }
            }
            if !viewModel.pendingUnbondings.isEmpty {
                Separator(color: Theme.colors.borderLight, opacity: 1)
                unbondingFooter
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func positionRow(for position: CosmosStakePositionRow) -> some View {
        VStack(spacing: 14) {
            validatorIdentityRow(for: position)
            stakedAmountRow(for: position)
            apyRow(for: position)
            Separator(color: Theme.colors.borderLight, opacity: 1)
            nextAwardRow(for: position)
            actionButtons(for: position)
        }
    }

    @ViewBuilder
    private func validatorIdentityRow(for position: CosmosStakePositionRow) -> some View {
        HStack(spacing: 8) {
            validatorAvatar(for: position)
            VStack(alignment: .leading, spacing: 2) {
                Text(position.validatorMoniker.isEmpty
                     ? truncated(position.validatorAddress)
                     : position.validatorMoniker)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                HStack {
                    Text(truncated(position.validatorAddress))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    statusBadge(for: position)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for position: CosmosStakePositionRow) -> some View {
        switch position.validatorStatus {
        case .active:
            Text("cosmosStakingValidatorActive".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertSuccess)
        case .churnedOut:
            Text("cosmosStakingValidatorChurnedOut".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertWarning)
        }
    }

    @ViewBuilder
    private func stakedAmountRow(for position: CosmosStakePositionRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HiddenBalanceText(String(format: "cosmosStakingStakedRowAmount".localized, formatAmount(position.stakedAmount), coin.ticker))
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            HiddenBalanceText(fiatString(for: position.stakedAmount))
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }

    @ViewBuilder
    private func apyRow(for position: CosmosStakePositionRow) -> some View {
        HStack(spacing: 4) {
            Icon(named: "percent", color: Theme.colors.textTertiary, size: 16)
            Text("cosmosStakingApy".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(apyDisplay(for: position))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.alertSuccess)
        }
    }

    @ViewBuilder
    private func nextAwardRow(for position: CosmosStakePositionRow) -> some View {
        HStack(spacing: 4) {
            Icon(named: "trophy", color: Theme.colors.textTertiary, size: 16)
            Text("cosmosStakingNextAward".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            HiddenBalanceText("\(formatAmount(position.pendingReward)) \(coin.ticker)")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }

    @ViewBuilder
    private func actionButtons(for position: CosmosStakePositionRow) -> some View {
        let isChurnedOut = position.validatorStatus == .churnedOut
        HStack(spacing: 8) {
            PrimaryButton(
                title: "cosmosStakingActionUndelegate".localized,
                type: .secondary,
                size: .small
            ) {
                onUndelegate(position)
            }
            .disabled(isChurnedOut)
            PrimaryButton(
                title: "cosmosStakingActionRedelegate".localized,
                type: .secondary,
                size: .small
            ) {
                onRedelegate(position)
            }
            PrimaryButton(
                title: "cosmosStakingActionDelegate".localized,
                size: .small
            ) {
                onDelegate(coin)
            }
        }
    }

    private func fiatString(for amount: Decimal) -> String {
        RateProvider.shared.fiatBalanceString(value: amount, coin: coin)
    }

    private func apyDisplay(for position: CosmosStakePositionRow) -> String {
        guard let apyPercent = position.apyPercent else { return "—" }
        return Self.apyFormatter.string(from: NSDecimalNumber(decimal: apyPercent)) ?? "—"
    }

    @ViewBuilder
    private func validatorAvatar(for position: CosmosStakePositionRow) -> some View {
        let source = position.validatorMoniker.isEmpty ? position.validatorAddress : position.validatorMoniker
        let monogram = String(source.prefix(1)).uppercased()
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.colors.primaryAccent3, Theme.colors.primaryAccent4],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(monogram)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private var unbondingFooter: some View {
        let unbondingDays = (try? CosmosStakingConfig.unbondingDays(for: coin.chain)) ?? 21
        let nextUnlock = viewModel.pendingUnbondings
            .flatMap(\.entries)
            .filter { $0.completionTime > Date() }
            .min(by: { $0.completionTime < $1.completionTime })?
            .completionTime
        let formatter: DateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter
        }()
        HStack {
            Text(String(format: "cosmosStakingUnbondingFooterDays".localized, unbondingDays))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
            Spacer()
            if let nextUnlock {
                Text(String(format: "cosmosStakingUnbondingFooterUnlock".localized, formatter.string(from: nextUnlock)))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        }
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return address.prefix(8) + "…" + address.suffix(4)
    }

    private func formatAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.numberStyle = .decimal
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}
