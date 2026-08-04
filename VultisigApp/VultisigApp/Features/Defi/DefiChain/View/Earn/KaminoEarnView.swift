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

    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
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
            if !viewModel.hasEnabledVaults {
                emptyStateView()
            } else {
                populatedState
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
            if row.apy30d != nil {
                apyRow(for: row)
            }
            if row.pnlToken != nil {
                pnlRow(for: row)
            }
            Separator(color: Theme.colors.borderLight, opacity: 1)
            actionRow(for: row)
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    /// The withdraw button appears only once the vault holds something. Whether
    /// that position can actually be withdrawn is the withdraw form's answer —
    /// it depends on whether the shares are staked in the vault's farm, which
    /// this row does not know and must not guess.
    @ViewBuilder
    private func actionRow(for row: KaminoEarnRow) -> some View {
        HStack(spacing: 12) {
            PrimaryButton(title: "kaminoEarnDeposit".localized, size: .smallFixed) {
                onDeposit(row.descriptor)
            }
            if row.tokenAmount > 0 {
                PrimaryButton(title: "kaminoEarnWithdraw".localized, type: .secondary, size: .smallFixed) {
                    onWithdraw(row.descriptor)
                }
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
                Text(row.name)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(String(format: "kaminoEarnCuratedBy".localized, row.curator))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.riskTier.title)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(riskColor(for: row.riskTier))
                }
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
                stalenessLabel(for: row)
            }
        }
    }

    /// How old an unconfirmed figure is.
    ///
    /// The card is cache-first and a failed refresh keeps the last-known
    /// position rather than blanking it — which is right, but it means the
    /// number on screen can be arbitrarily old with nothing saying so. This is
    /// the whole disclosure: a live row shows nothing, an unconfirmed one says
    /// when it was last true.
    ///
    /// Deliberately NOT a chain-level error banner. `DefiChainMainScreen`
    /// reserves that for bonds, and the stake and LP segments also keep their
    /// rows silently on failure; the difference this earns is that a Kamino
    /// figure has no other source in the app, so its age is worth a line.
    @ViewBuilder
    private func stalenessLabel(for row: KaminoEarnRow) -> some View {
        if !row.isLive, let lastUpdated = row.lastUpdated {
            Text(String(format: "kaminoEarnLastUpdated".localized, Self.relativeDate(lastUpdated)))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertWarning)
        }
    }

    @ViewBuilder
    private func apyRow(for row: KaminoEarnRow) -> some View {
        if let apyText = apyDisplay(for: row) {
            HStack(spacing: 4) {
                Icon(.circlePercentage, color: Theme.colors.textTertiary, size: 16)
                Text("kaminoEarnApy30d".localized)
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
    private func pnlRow(for row: KaminoEarnRow) -> some View {
        if let pnl = row.pnlToken {
            HStack(spacing: 4) {
                Text("kaminoEarnPnl".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                HiddenBalanceText("\(formatAmount(pnl)) \(row.coin?.ticker ?? "")")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(pnl < 0 ? Theme.colors.alertError : Theme.colors.alertSuccess)
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

    /// Localised "2 minutes ago" style age, in the device's own locale.
    private static func relativeDate(_ date: Date) -> String {
        KaminoEarnFormatters.relativeDate.localizedString(for: date, relativeTo: .now)
    }

    private func formatAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = KaminoEarnFormatters.amountFractionDigits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}
