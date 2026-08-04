//
//  KaminoEarnView.swift
//  VultisigApp
//
//  Earn segment of the Solana DeFi chain tab: one card per curated Kamino vault
//  the user enabled, plus a total across them.
//
//  Each card shows the vault's name, its curator and risk tier, the deposited
//  amount in the underlying token with its fiat value, the 30-day APY and the
//  lifetime profit and loss, and opens the deposit form. Withdrawing is not
//  offered yet — the farm-staked withdraw transaction has never been observed,
//  and the validator refuses a shape it has not seen.
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
            ForEach(viewModel.rows) { row in
                vaultCard(for: row)
            }
        }
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

    @ViewBuilder
    private func vaultCard(for row: KaminoEarnRow) -> some View {
        VStack(spacing: 14) {
            vaultIdentityRow(for: row)
            Separator(color: Theme.colors.borderLight, opacity: 1)
            depositedRow(for: row)
            // Kept on screen while the value is still being fetched, rather than
            // appearing once it lands. A row that pops into existence reads as a
            // layout jump; a labelled row with a shimmering value says which
            // figure the screen is waiting on. Both are genuinely absent until
            // the API answers — unlike the deposited amount, whose zero is a
            // real value, so nothing there is placeheld.
            if row.apy30d != nil || viewModel.isLoading {
                apyRow(for: row)
            }
            if row.pnlToken != nil || viewModel.isLoading {
                pnlRow(for: row)
            }
            Separator(color: Theme.colors.borderLight, opacity: 1)
            depositButton(for: row)
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    /// Deposit only. A withdraw button would need a withdraw transaction the app
    /// can validate, and the farm-staked shape every one of these positions is in
    /// has never been observed.
    private func depositButton(for row: KaminoEarnRow) -> some View {
        PrimaryButton(title: "kaminoEarnDeposit".localized, size: .smallFixed) {
            onDeposit(row.descriptor)
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

    @ViewBuilder
    private func depositedRow(for row: KaminoEarnRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("kaminoEarnDeposited".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HiddenBalanceText("\(formatAmount(row.tokenAmount)) \(row.coin?.ticker ?? "")")
                    .font(Theme.fonts.priceBodyL)
                    .foregroundStyle(Theme.colors.textPrimary)
                HiddenBalanceText(fiatString(for: row))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
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

    @ViewBuilder
    private func pnlRow(for row: KaminoEarnRow) -> some View {
        HStack(spacing: 4) {
            Text("kaminoEarnPnl".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            if let pnl = row.pnlToken {
                HiddenBalanceText("\(formatAmount(pnl)) \(row.coin?.ticker ?? "")")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(pnlColor(pnl))
            } else {
                valuePlaceholder(width: 72)
            }
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
        guard let coin = row.coin else { return .zero }
        return RateProvider.shared.fiatBalance(value: row.tokenAmount, coin: coin)
    }

    private func fiatString(for row: KaminoEarnRow) -> String {
        fiatValue(for: row).formatToFiat(includeCurrencySymbol: true)
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
