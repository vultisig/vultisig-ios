//
//  BondRewardHistorySheet.swift
//  VultisigApp
//
//  "Total Rewards Earned": the live Upcoming share plus one dated row per
//  past reward, newest first. Opened from the bonded node card's Last Reward
//  cell (THOR and Maya, one row per churn) and from the TCY stake card's
//  Estimated Reward cell (one row per daily payout) — all feed it the same
//  `BondRewardHistoryEntry` shape.
//

import SwiftUI

struct BondRewardHistorySheet: View {
    @ObservedObject var viewModel: BondRewardHistoryViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            header
            Separator(color: Theme.colors.border, opacity: 1)
            historyList
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.colors.bgPrimary)
        .onAppear { viewModel.loadIfNeeded() }
        .onDisappear { viewModel.cancelLoad() }
        #if os(macOS)
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark, action: onDismiss)
            }
        }
        #endif
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("totalRewardsEarned".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            HiddenBalanceText(viewModel.coin.formatWithTicker(value: viewModel.total))
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)

            Text(viewModel.subtitle)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            if !viewModel.isHistoryComplete {
                Text("rewardHistoryPartial".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var historyList: some View {
        ScrollView {
            // Lazy: TCY staking pays daily, so its history runs to hundreds of rows.
            LazyVStack(spacing: 12) {
                if let upcomingAmount = viewModel.upcomingAmount {
                    upcomingRow(upcomingAmount)
                }

                if viewModel.isLoading, viewModel.history.isEmpty {
                    ProgressView()
                        .padding(.top, 24)
                } else if let loadError = viewModel.loadError {
                    Text(loadError)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .padding(.top, 24)
                } else {
                    ForEach(viewModel.history) { entry in
                        row(amount: entry.amount, amountPrefix: nil) {
                            datePill(entry.date)
                        }
                    }
                }
            }
            .padding(.trailing, 12)
        }
    }

    private func upcomingRow(_ amount: Decimal) -> some View {
        row(amount: amount, amountPrefix: "~") {
            upcomingBadge
        }
    }

    @ViewBuilder
    private func row<Trailing: View>(
        amount: Decimal,
        amountPrefix: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: viewModel.coin.logo,
                size: CGSize(width: 32, height: 32),
                ticker: viewModel.coin.ticker,
                tokenChainLogo: nil
            )

            HStack(spacing: 2) {
                if let amountPrefix {
                    Text(amountPrefix)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                HiddenBalanceText(viewModel.coin.formatWithTicker(value: amount))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            Spacer()
            trailing()
        }
    }

    private var upcomingBadge: some View {
        Text("upcoming".localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.alertWarning)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.colors.bgAlert))
    }

    private func datePill(_ date: Date) -> some View {
        Text(CustomDateFormatter.formatMonthDayFullYear(date))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(Theme.colors.border, lineWidth: 1))
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            BondRewardHistorySheet(
                viewModel: BondRewardHistoryViewModel(
                    vault: .example,
                    chain: .thorChain,
                    coin: .example,
                    node: .init(
                        node: .init(coin: .example, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", state: .active),
                        amount: 500,
                        apy: 0.1,
                        nextReward: 18,
                        lastReward: 25,
                        vault: .example
                    )
                ),
                onDismiss: {}
            )
        }
        .environmentObject(HomeViewModel())
}
