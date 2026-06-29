//
//  SolanaStakeDefiView.swift
//  VultisigApp
//
//  Solana native-staking segment of the DeFi chain tab. Unlike Cosmos's
//  per-validator delegation list, Solana staking is per-STAKE-ACCOUNT — a wallet
//  holds N accounts, each with its own validator and activation lifecycle. So
//  this renders one card per stake account:
//
//    - "Total Staked SOL" summary card with a "Delegate to New Validator" CTA
//    - Per-stake-account card: validator identity, delegated amount + fiat,
//      activation/cooldown status badge (Activating / Active / Deactivating /
//      Inactive), APY (when resolved), rent-reserve line, and the four action
//      buttons — Unstake / Move / Withdraw / Delegate.
//
//  Each action hands off to the shared `FunctionTransactionType.solana*` enum
//  cases via the closures, which route through `FunctionTransactionScreen` into
//  the per-flow Solana staking VMs (built on prior PRs). NO claim path — Solana
//  rewards auto-compound into the stake.
//
//  Gating: Unstake is enabled only while active/activating, Move only while
//  active (a stable delegation to move), Withdraw only once fully inactive
//  (cooled down). Move is WHOLE-ACCOUNT only in v1 (wallet-core has no Split).
//

import SwiftUI

private enum SolanaStakeDefiFormatters {
    static let amountFractionDigits = 6

    static let apy: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

struct SolanaStakeDefiView: View {
    let coin: Coin
    let totalFiat: String
    @ObservedObject var viewModel: SolanaStakeDefiViewModel
    var onDelegate: (Coin) -> Void
    var onUnstake: (SolanaStakeAccountRow) -> Void
    var onWithdraw: (SolanaStakeAccountRow) -> Void
    var onMoveStake: (SolanaStakeAccountRow) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            } else {
                populatedState
            }
        }
    }

    // Always render the total-staked card (and its "Delegate to New Validator"
    // CTA) so a user with zero stake accounts can still start staking — Solana
    // staking has no empty state. The per-account list only appears once the
    // wallet actually holds stake accounts.
    @ViewBuilder
    private var populatedState: some View {
        VStack(spacing: 16) {
            totalStakedCard
            if !viewModel.rows.isEmpty {
                stakeAccountsCard
            }
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
                    Text(String(format: "solanaStakingTotalStaked".localized, coin.ticker))
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

            PrimaryButton(title: "solanaStakingDelegateNewValidator".localized) {
                onDelegate(coin)
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    @ViewBuilder
    private var stakeAccountsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("solanaStakingActiveAccounts".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer()
            }
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                accountRow(for: row)
                if index < viewModel.rows.count - 1 {
                    Separator(color: Theme.colors.borderLight, opacity: 1)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    @ViewBuilder
    private func accountRow(for row: SolanaStakeAccountRow) -> some View {
        VStack(spacing: 14) {
            validatorIdentityRow(for: row)
            stakedAmountRow(for: row)
            if row.apyPercent != nil {
                apyRow(for: row)
            }
            rentReserveRow(for: row)
            gatingNotice(for: row)
            Separator(color: Theme.colors.borderLight, opacity: 1)
            actionButtons(for: row)
        }
    }

    @ViewBuilder
    private func validatorIdentityRow(for row: SolanaStakeAccountRow) -> some View {
        HStack(spacing: 8) {
            validatorAvatar(for: row)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.validatorName)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                HStack {
                    Text(SolanaValidator.truncatedPubkey(row.stakeAccount.pubkey))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    statusBadge(for: row)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for row: SolanaStakeAccountRow) -> some View {
        switch row.activationState {
        case .active:
            statusText("solanaStakingStateActive".localized, color: Theme.colors.alertSuccess)
        case .activating:
            statusText("solanaStakingStateActivating".localized, color: Theme.colors.alertWarning)
        case .deactivating:
            statusText("solanaStakingStateDeactivating".localized, color: Theme.colors.alertWarning)
        case .inactive:
            statusText("solanaStakingStateInactive".localized, color: Theme.colors.textTertiary)
        }
    }

    @ViewBuilder
    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func stakedAmountRow(for row: SolanaStakeAccountRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HiddenBalanceText(String(format: "solanaStakingStakedRowAmount".localized, formatAmount(row.delegatedAmount), coin.ticker))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            HiddenBalanceText(fiatString(for: row.delegatedAmount))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }

    @ViewBuilder
    private func apyRow(for row: SolanaStakeAccountRow) -> some View {
        if let apyText = apyDisplay(for: row) {
            HStack(spacing: 4) {
                Icon(named: "percent", color: Theme.colors.textTertiary, size: 16)
                Text("solanaStakingApy".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text(apyText)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
        }
    }

    @ViewBuilder
    private func rentReserveRow(for row: SolanaStakeAccountRow) -> some View {
        HStack(spacing: 4) {
            Text("solanaStakingRentReserve".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text("\(formatAmount(row.rentReserve)) \(coin.ticker)")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }

    /// Activation/cooldown gating copy. Surfaced only for the non-active states
    /// so an active row stays uncluttered.
    @ViewBuilder
    private func gatingNotice(for row: SolanaStakeAccountRow) -> some View {
        if let notice = gatingNoticeText(for: row) {
            HStack {
                Text(notice)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer(minLength: 8)
            }
        }
    }

    private func gatingNoticeText(for row: SolanaStakeAccountRow) -> String? {
        switch row.activationState {
        case .activating:
            return "solanaStakingActivatingNotice".localized
        case .deactivating:
            return "solanaStakingDeactivatingRowNotice".localized
        case .inactive:
            return "solanaStakingInactiveNotice".localized
        case .active:
            return nil
        }
    }

    @ViewBuilder
    private func actionButtons(for row: SolanaStakeAccountRow) -> some View {
        HStack(spacing: 8) {
            if row.canWithdraw {
                PrimaryButton(
                    title: "solanaStakingActionWithdraw".localized,
                    size: .smallFixed
                ) {
                    onWithdraw(row)
                }
            } else {
                PrimaryButton(
                    title: "solanaStakingActionUnstake".localized,
                    type: .secondary,
                    size: .smallFixed
                ) {
                    onUnstake(row)
                }
                .disabled(!row.canUnstake)
                PrimaryButton(
                    title: "solanaStakingActionMove".localized,
                    type: .secondary,
                    size: .smallFixed
                ) {
                    onMoveStake(row)
                }
                .disabled(!row.canMoveStake)
                PrimaryButton(
                    title: "solanaStakingActionDelegate".localized,
                    size: .smallFixed
                ) {
                    onDelegate(coin)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func validatorAvatar(for row: SolanaStakeAccountRow) -> some View {
        let monogram = String(row.validatorName.prefix(1)).uppercased()
        if let logoURL = row.validatorLogoURL {
            AsyncImageView(
                logo: logoURL.absoluteString,
                size: CGSize(width: 36, height: 36),
                ticker: monogram,
                tokenChainLogo: nil
            )
        } else {
            ZStack {
                Circle().fill(Theme.colors.bgSurface2)
                Text(monogram)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .frame(width: 36, height: 36)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.colors.bgSurface1)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Theme.colors.border, lineWidth: 1)
    }

    private func fiatString(for amount: Decimal) -> String {
        RateProvider.shared.fiatBalanceString(value: amount, coin: coin)
    }

    private func apyDisplay(for row: SolanaStakeAccountRow) -> String? {
        guard let apyPercent = row.apyPercent else { return nil }
        return SolanaStakeDefiFormatters.apy.string(from: NSDecimalNumber(decimal: apyPercent))
    }

    private func formatAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = SolanaStakeDefiFormatters.amountFractionDigits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}
