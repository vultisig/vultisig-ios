//
//  CosmosStakeDefiView.swift
//  VultisigApp
//
//  LUNA / LUNC stake segment of the DeFi chain tab. Renders an empty
//  state (Figma `75718:98358`) when no delegations exist, or a populated
//  layout (Figma `75718:98399`) with:
//
//    - "Total Staked %@" summary card
//    - One card per active delegation with Delegate / Undelegate /
//      Redelegate / Claim action buttons
//    - 21-day unbonding-lock notice + per-validator unbonding entries
//      when present
//
//  Action buttons hand off to the shared
//  `FunctionTransactionType.cosmos*` enum cases, which route through
//  `FunctionTransactionScreen` and into the per-flow Cosmos staking VMs.
//

import SwiftUI

struct CosmosStakeDefiView: View {
    let coin: Coin
    @ObservedObject var viewModel: CosmosStakeDefiViewModel
    var onDelegate: (Coin) -> Void
    var onUndelegate: (CosmosStakePositionRow) -> Void
    var onRedelegate: (CosmosStakePositionRow) -> Void
    var onClaim: ([CosmosStakePositionRow]) -> Void

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
        ActionBannerView(
            title: String(format: "cosmosStakingDelegateTitle".localized, coin.ticker),
            subtitle: "cosmosStakingDelegateStubSubtitle".localized,
            buttonTitle: String(format: "cosmosStakingDelegateTitle".localized, coin.ticker),
            action: { onDelegate(coin) }
        )
    }

    @ViewBuilder
    private var populatedState: some View {
        VStack(spacing: 16) {
            totalStakedCard
            ForEach(viewModel.positions) { position in
                positionCard(for: position)
            }
            if !viewModel.pendingUnbondings.isEmpty {
                pendingUnbondingsSection
            }
            // Bottom delegate-CTA so the user can add to any validator
            ActionBannerView(
                title: "cosmosStakingActionDelegate".localized,
                subtitle: "cosmosStakingDelegateStubSubtitle".localized,
                buttonTitle: String(format: "cosmosStakingDelegateTitle".localized, coin.ticker),
                action: { onDelegate(coin) }
            )
        }
    }

    @ViewBuilder
    private var totalStakedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "cosmosStakingTotalStaked".localized, coin.ticker))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text("\(formatAmount(viewModel.totalStaked)) \(coin.ticker)")
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)
            HStack(spacing: 12) {
                let claimable = viewModel.positions.filter { $0.pendingReward > 0 }
                if !claimable.isEmpty {
                    PrimaryButton(
                        title: "cosmosStakingActionClaim".localized,
                        type: .secondary,
                        size: .small
                    ) {
                        onClaim(claimable)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func positionCard(for position: CosmosStakePositionRow) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.validatorMoniker.isEmpty
                         ? truncated(position.validatorAddress)
                         : position.validatorMoniker)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(truncated(position.validatorAddress))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(formatAmount(position.stakedAmount)) \(coin.ticker)")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    if position.pendingReward > 0 {
                        Text("+\(formatAmount(position.pendingReward))")
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.alertSuccess)
                    }
                }
            }
            HStack(spacing: 8) {
                PrimaryButton(
                    title: "cosmosStakingActionDelegate".localized,
                    type: .secondary,
                    size: .small
                ) {
                    onDelegate(coin)
                }
                PrimaryButton(
                    title: "cosmosStakingActionUndelegate".localized,
                    type: .secondary,
                    size: .small
                ) {
                    onUndelegate(position)
                }
                PrimaryButton(
                    title: "cosmosStakingActionRedelegate".localized,
                    type: .secondary,
                    size: .small
                ) {
                    onRedelegate(position)
                }
            }
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var pendingUnbondingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cosmosStakingPendingUnbondings".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            ForEach(viewModel.pendingUnbondings, id: \.validatorAddress) { unbonding in
                unbondingRow(for: unbonding)
            }
        }
    }

    @ViewBuilder
    private func unbondingRow(for unbonding: CosmosUnbondingDelegation) -> some View {
        let totalBalance = unbonding.entries.reduce(into: Decimal(0)) { $0 += $1.balance }
        let divisor = pow(Decimal(10), coin.decimals)
        let displayAmount = totalBalance / divisor
        let nextUnlock = unbonding.entries
            .filter { $0.completionTime > Date() }
            .sorted { $0.completionTime < $1.completionTime }
            .first?
            .completionTime
        let formatter: DateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter
        }()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(truncated(unbonding.validatorAddress))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Text("\(formatAmount(displayAmount)) \(coin.ticker)")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            if let nextUnlock {
                Text(String(
                    format: "cosmosStakingUnbondingLockNotice".localized,
                    (try? CosmosStakingConfig.unbondingDays(for: coin.chain)) ?? 21,
                    formatter.string(from: nextUnlock)
                ))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
