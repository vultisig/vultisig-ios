//
//  KaminoEarnView.swift
//  VultisigApp
//
//  Earn segment of the Solana DeFi chain tab: one card per curated Kamino vault
//  the user enabled, plus a total across them.
//
//  Each card shows the vault's name, its curator and risk tier, the deposited
//  amount in the underlying token with its fiat value, the 30-day APY and the
//  lifetime profit and loss, and opens the deposit and withdraw forms.
//

import SwiftUI

private enum KaminoEarnFormatters {
    static let amountFractionDigits = 6

    static let apy: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

struct KaminoEarnView<EmptyState: View>: View {
    @ObservedObject var viewModel: KaminoEarnViewModel
    let onDeposit: (KaminoVaultDescriptor) -> Void
    let onWithdraw: (KaminoVaultDescriptor) -> Void
    @ViewBuilder var emptyStateView: () -> EmptyState

    // Gated on the per-vault opt-in exactly like the stake segment: until the
    // user selects at least one vault under "Manage positions", only the
    // empty-state banner shows. Once enabled, the cards ALWAYS render — a vault
    // with no deposit yet still has a card, and a card must never vanish on a
    // pull-to-refresh (cache-first: persist + refresh, never blank).
    var body: some View {
        Group {
            if viewModel.hasEnabledVaults {
                populatedState
            } else if viewModel.isLoading {
                // Enabled, but nothing seeded to paint yet. `refresh` returns
                // before it sets `isLoading` when the user has enabled nothing,
                // so this branch cannot swallow the opt-in banner.
                KaminoEarnPositionSkeletonView()
            } else {
                emptyStateView()
            }
        }
    }

    @ViewBuilder
    private var populatedState: some View {
        VStack(spacing: 16) {
            totalCard
            ForEach(sortedRows) { row in
                vaultCard(for: row)
            }
        }
    }

    /// Match each vault card's painted fiat figure. Registry order is only a
    /// deterministic tie-breaker; it never outranks a funded position.
    private var sortedRows: [KaminoEarnRow] {
        DefiPositionOrdering.descending(
            viewModel.rows,
            value: { fiatValue(for: $0) },
            tieBreak: \.id
        )
    }

    @ViewBuilder
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("kaminoEarnTitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            HiddenBalanceText(totalFiat)
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    /// Two states, as the design draws them: a vault the user holds nothing in
    /// is its identity, its rate and one full-width Deposit — there is no
    /// position to describe, and rows of zeros describe nothing. A vault they
    /// hold something in gains the deposited and earned figures, and the
    /// separator that sets its two actions apart.
    @ViewBuilder
    private func vaultCard(for row: KaminoEarnRow) -> some View {
        VStack(spacing: 14) {
            vaultIdentityRow(for: row)
            if row.hasPosition {
                depositedRow(for: row)
                // Kept on screen while the value is still being fetched, rather
                // than appearing once it lands. A row that pops into existence
                // reads as a layout jump; a labelled row with a shimmering value
                // says which figure the screen is waiting on.
                if row.pnlToken != nil || viewModel.isLoading {
                    earnedRow(for: row)
                }
            }
            if row.apy30d != nil || viewModel.isLoading {
                apyRow(for: row)
            }
            if row.hasPosition {
                Separator(color: Theme.colors.borderLight, opacity: 1)
            }
            actionRow(for: row)
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    /// The withdraw button appears once the vault is known to hold something —
    /// or while that is still unknown, because a position must never be made
    /// unreachable by a read that failed. Deposit takes the whole width when it
    /// is alone: a half-width button beside empty space reads as a missing
    /// control rather than an absent one.
    ///
    /// Whether the position can actually be withdrawn is the withdraw form's
    /// answer — it depends on whether the shares are staked in the vault's farm,
    /// which this row does not know and must not guess.
    @ViewBuilder
    private func actionRow(for row: KaminoEarnRow) -> some View {
        // `.smallFixed` has no horizontal padding of its own, so each button
        // takes an equal share of the row: two side by side when there is a
        // position, one across the full width when there is not.
        HStack(spacing: 16) {
            if row.offersWithdraw {
                PrimaryButton(title: "kaminoEarnWithdraw".localized, type: .secondary, size: .smallFixed) {
                    onWithdraw(row.descriptor)
                }
            }
            PrimaryButton(title: "kaminoEarnDeposit".localized, size: .smallFixed) {
                onDeposit(row.descriptor)
            }
        }
    }

    @ViewBuilder
    private func vaultIdentityRow(for row: KaminoEarnRow) -> some View {
        HStack(spacing: 12) {
            if let coin = row.coin {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: coin.ticker,
                    tokenChainLogo: nil
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                // The risk tier rides on the name line, not the curator line.
                // Sharing a line with the curator left roughly 180pt for a string
                // that needs ~190 ("Curated by Steakhouse Finance"), so the
                // curator truncated while the name line beside it sat half empty.
                // The tier is two short fixed strings and is pinned at its
                // intrinsic width, so the name yields first and the curator gets
                // the whole line below.
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.riskTier.title)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(riskColor(for: row.riskTier))
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(String(format: "kaminoEarnCuratedBy".localized, row.curator))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The amount rides INSIDE the label and the fiat sits opposite it, which is
    /// how the design draws both figure rows — and it is what lets the deposited
    /// and earned lines read as a pair rather than as two stacked columns.
    @ViewBuilder
    private func depositedRow(for row: KaminoEarnRow) -> some View {
        figureRow(
            label: String(format: "kaminoEarnDeposited".localized, tokenString(row.tokenAmount, in: row)),
            fiat: fiatString(fiatValue(for: row)),
            valueColor: Theme.colors.textPrimary
        )
    }

    @ViewBuilder
    private func apyRow(for row: KaminoEarnRow) -> some View {
        HStack(spacing: 4) {
            Icon(.circlePercentage, color: Theme.colors.textTertiary, size: 16)
            Text("kaminoEarnApy30d".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            if let apyText = apyDisplay(for: row) {
                Text(apyText)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertSuccess)
            } else {
                valuePlaceholder(width: 54)
            }
        }
    }

    /// Stands in for a figure this refresh has not produced yet. Sized to the
    /// value it replaces so the row does not resize when the number arrives.
    private func valuePlaceholder(width: CGFloat) -> some View {
        Theme.radius.xs.shape
            .fill(Theme.colors.borderLight.opacity(0.3))
            .frame(width: width, height: 14)
            .redacted(reason: .placeholder)
            .shimmer()
            .accessibilityHidden(true)
    }

    /// What the position has made, in the underlying token and in fiat.
    ///
    /// The figure is the vault's lifetime profit and loss — on a lending vault
    /// that is the interest it has accrued, which is what "earned" means. A
    /// NEGATIVE one is not, so it changes the label rather than only the colour:
    /// "Earned: -3 USDC" in red still asserts the loss was earned, and the
    /// figure is rendered unsigned beside a label that names it.
    @ViewBuilder
    private func earnedRow(for row: KaminoEarnRow) -> some View {
        if let pnl = row.pnlToken {
            figureRow(
                label: String(
                    format: (pnl < 0 ? "kaminoEarnLost" : "kaminoEarnEarned").localized,
                    tokenString(abs(pnl), in: row)
                ),
                fiat: fiatString(abs(fiatValue(pnl, in: row))),
                valueColor: pnlColor(pnl)
            )
        } else {
            HStack(alignment: .firstTextBaseline) {
                valuePlaceholder(width: 120)
                Spacer()
                valuePlaceholder(width: 64)
            }
        }
    }

    /// One labelled figure with its fiat value opposite. The label carries the
    /// token amount, so it is hidden along with the value when balances are
    /// hidden — a row reading "Earned: 200 USDC" beside a masked fiat figure
    /// would defeat the point of hiding it.
    @ViewBuilder
    private func figureRow(label: String, fiat: String, valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HiddenBalanceText(label)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(valueColor)
                .lineLimit(1)
            Spacer(minLength: 4)
            HiddenBalanceText(fiat)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    /// Fiat across every enabled vault. Summed per row because the vaults do not
    /// share an underlying token — dollars and SOL cannot be added before the
    /// rate is applied.
    private var totalFiat: String {
        viewModel.rows
            .map { fiatValue(for: $0) }
            .reduce(Decimal.zero, +)
            .formatToFiat(includeCurrencySymbol: true)
    }

    private func fiatValue(for row: KaminoEarnRow) -> Decimal {
        fiatValue(row.tokenAmount, in: row)
    }

    /// Any token amount of this row's asset, in fiat. Used for the deposit and
    /// for what it has earned, which are the same asset at the same rate.
    private func fiatValue(_ amount: Decimal, in row: KaminoEarnRow) -> Decimal {
        guard let coin = row.coin else { return .zero }
        return RateProvider.shared.fiatBalance(value: amount, coin: coin)
    }

    private func fiatString(_ value: Decimal) -> String {
        value.formatToFiat(includeCurrencySymbol: true)
    }

    private func tokenString(_ amount: Decimal, in row: KaminoEarnRow) -> String {
        "\(formatAmount(amount)) \(row.coin?.ticker ?? "")"
    }

    /// Green means the position made money, red means it lost some. Exactly zero
    /// means neither, and it is the number every vault the user has never
    /// deposited into shows — a card sitting at 0 USDC read as a gain in green.
    private func pnlColor(_ pnl: Decimal) -> Color {
        if pnl > 0 { return Theme.colors.alertSuccess }
        if pnl < 0 { return Theme.colors.alertError }
        return Theme.colors.textPrimary
    }

    private func riskColor(for tier: KaminoRiskTier) -> Color {
        switch tier {
        case .conservative:
            Theme.colors.textTertiary
        case .privateCredit:
            // Lending against tokenized private credit is a materially different
            // risk and must not read as the same product as the plain vaults.
            Theme.colors.alertWarning
        }
    }

    private var cardBackground: some View {
        Theme.radius.xl.shape
            .fill(Theme.colors.bgSurface1)
    }

    private var cardBorder: some View {
        Theme.radius.xl.shape
            .stroke(Theme.colors.border, lineWidth: 1)
    }

    private func apyDisplay(for row: KaminoEarnRow) -> String? {
        guard let apy30d = row.apy30d else { return nil }
        return KaminoEarnFormatters.apy.string(from: NSDecimalNumber(decimal: apy30d))
    }

    private func formatAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = KaminoEarnFormatters.amountFractionDigits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}
