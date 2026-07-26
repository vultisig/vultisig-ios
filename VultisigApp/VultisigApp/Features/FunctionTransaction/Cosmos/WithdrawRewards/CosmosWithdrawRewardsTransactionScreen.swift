//
//  CosmosWithdrawRewardsTransactionScreen.swift
//  VultisigApp
//
//  Selection-driven claim-rewards screen for LUNA / LUNC. Shows the
//  per-validator pending reward list with a checkbox column, a
//  "Select all" toggle, the total claim amount, the estimated fee
//  (scaling with selection count) and an inline insufficient-fee
//  warning when the pre-flight check fails.
//

import SwiftUI

struct CosmosWithdrawRewardsTransactionScreen: View {
    @StateObject private var viewModel: CosmosWithdrawRewardsTransactionViewModel
    let onVerify: (TransactionBuilder) -> Void

    init(
        viewModel: CosmosWithdrawRewardsTransactionViewModel,
        onVerify: @escaping (TransactionBuilder) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onVerify = onVerify
    }

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                header
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.candidates, id: \.validatorAddress) { candidate in
                            row(for: candidate)
                        }
                    }
                }
                footer
            }
        }
        .screenTitle("cosmosStakingClaimRewardsTitle".localized)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("cosmosStakingClaimRewardsSelectValidators".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Button(action: viewModel.toggleSelectAll) {
                    Text("cosmosStakingClaimRewardsSelectAll".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.primaryAccent3)
                }
                .buttonStyle(.plain)
            }
            if viewModel.hitBatchCapWarning {
                HStack(spacing: 8) {
                    Icon(.circleInfo, color: Theme.colors.alertWarning, size: 14)
                    Text(String(
                        format: "cosmosStakingClaimRewardsCapMessage".localized,
                        CosmosWithdrawRewardsTransactionViewModel.maxBatchSize
                    ))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                }
                .padding(10)
                .background(Theme.colors.bgSurface1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func row(for candidate: CosmosWithdrawRewardsCandidate) -> some View {
        let isSelected = viewModel.selectedValidators.contains(candidate.validatorAddress)
        return Button {
            viewModel.toggle(validator: candidate)
        } label: {
            HStack(spacing: 12) {
                checkbox(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.validatorMoniker.isEmpty
                         ? truncated(candidate.validatorAddress)
                         : candidate.validatorMoniker)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(truncated(candidate.validatorAddress))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(formatAmount(candidate.pendingReward))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func checkbox(isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected
                        ? Theme.colors.primaryAccent3
                        : Theme.colors.borderLight,
                    lineWidth: 1.5
                )
                .background(
                    isSelected
                        ? Theme.colors.primaryAccent3.opacity(0.2)
                        : Color.clear
                )
                .frame(width: 20, height: 20)
            if isSelected {
                Icon(.check, color: Theme.colors.primaryAccent3, size: 12)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                Text("cosmosStakingClaimRewardsTotalRewards".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text("\(formatAmount(viewModel.totalSelectedReward)) \(viewModel.coin.ticker)")
                    .font(Theme.fonts.priceBodyL)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            HStack {
                Text("cosmosStakingClaimRewardsEstimatedFee".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text("\(formatAmount(viewModel.estimatedFee)) \(viewModel.coin.ticker)")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            if !viewModel.hasSufficientBalanceForFee {
                HStack(spacing: 8) {
                    Icon(.circleInfo, color: Theme.colors.alertError, size: 14)
                    Text(String(
                        format: "cosmosStakingInsufficientGas".localized,
                        viewModel.coin.ticker
                    ))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.alertError)
                    Spacer()
                }
            }

            PrimaryButton(title: "continue".localized) {
                guard let builder = viewModel.transactionBuilder else { return }
                onVerify(builder)
            }
            .disabled(!viewModel.validForm)
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
