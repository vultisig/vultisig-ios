//
//  PerpsSheets.swift
//  VultisigApp
//
//  Perps sheets: add funds, plus the small ones
//  (learn more, account, market info). Same shape as the ticket: a centered
//  amount, one line, a few rows, one action.
//

import SwiftUI

struct PerpsFundsSheet: View {
    let onReview: (PerpsReviewDocument) -> Void
    @StateObject private var viewModel: PerpsFundsViewModel

    init(account: PerpsAccountSnapshot?, vault: PerpsVaultContext, prefill: Decimal? = nil,
         onReview: @escaping (PerpsReviewDocument) -> Void) {
        self.onReview = onReview
        _viewModel = StateObject(wrappedValue: PerpsFundsViewModel(account: account, vault: vault, prefill: prefill))
    }

    var body: some View {
        VStack(spacing: 24) {
            PerpsSheetTitle(title: "perpsAddFunds".localized)
            VStack(spacing: 8) {
                PerpsAmountInput(text: viewModel.amountText, prefix: "", suffix: " USDC", isFocused: true, accessibilityID: "perpsFundsAmount")
                HStack(spacing: 8) {
                    Text(String(format: "perpsInYourVault".localized,
                                PerpsFlows.usdc(viewModel.source)))
                        .font(Theme.fonts.bodySRegular)
                        .foregroundStyle(Theme.colors.textTertiary)
                    PrimaryButton(title: "perpsMax".localized, type: .secondary, size: .mini) { viewModel.applyMax() }
                        .fixedSize()
                }
                Text(viewModel.issue ?? " ")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertError)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
            PerpsCard {
                PerpsRow(title: "perpsFrom".localized, value: "perpsVaultArbitrum".localized)
                PerpsRow(title: "perpsTo".localized, value: "perpsTradingAccountShort".localized,
                         showsDivider: true)
            }
            PrimaryButton(title: "perpsReview".localized) {
                guard let document = viewModel.reviewDocument() else { return }
                onReview(document)
            }
            .disabled(!viewModel.canReview)
            .accessibilityIdentifier("perpsFundsReview")
            PerpsKeypad { viewModel.amountText = PerpsKeypadKey.apply($0, to: viewModel.amountText) }
        }
        .perpsSheetChrome()
    }
}

/// Three plain facts before a first trade.
struct PerpsLearnMoreSheet: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PerpsSheetTitle(title: "perpsLearnTitle".localized)
            ForEach([("perpsLearnLeverageTitle", "perpsLearnLeverageBody"),
                     ("perpsLearnLiquidationTitle", "perpsLearnLiquidationBody"),
                     ("perpsLearnVaultTitle", "perpsLearnVaultBody")], id: \.0) { title, body in
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.localized).font(Theme.fonts.bodyMMedium).foregroundStyle(Theme.colors.textPrimary)
                    Text(body.localized).font(Theme.fonts.bodySRegular).foregroundStyle(Theme.colors.textTertiary)
                }
            }
            PrimaryButton(title: "perpsGotIt".localized, action: onDone)
        }
        .perpsSheetChrome()
    }
}

/// , behind "$X available >" on the funded hub: two numbers that
/// add up to the equity, then Add funds and Withdraw side by side.
struct PerpsAccountSheet: View {
    let summary: PerpsAccountSummary
    let onAddFunds: () -> Void
    let onWithdraw: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            PerpsSheetTitle(title: "perpsTradingAccountShort".localized)
            VStack(spacing: 10) {
                PerpsCard {
                    PerpsRow(title: "perpsAvailable".localized, value: PerpsFormat.usd(summary.available))
                    PerpsRow(title: "perpsInPositions".localized, value: PerpsFormat.usd(summary.inPositions), showsDivider: true)
                }
                PerpsFootnote(text: "perpsOnlyAvailableWithdraws".localized)
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "perpsAddFunds".localized, leadingView: { Icon(.plus, color: Theme.colors.textPrimary, size: 16) }, type: .secondary, action: onAddFunds)
                    .accessibilityIdentifier("perpsAccountAddFunds")
                PrimaryButton(title: "perpsWithdraw".localized, leadingView: { Icon(.upload, color: Theme.colors.textPrimary, size: 16) }, type: .secondary, action: onWithdraw)
                    .accessibilityIdentifier("perpsAccountWithdraw")
            }
            .padding(.top, 8)
        }
        .perpsSheetChrome()
    }
}

/// Funding, open interest and volume, one tap away from the market screen.
struct PerpsMarketInfoSheet: View {
    let market: PerpsMarket

    var body: some View {
        VStack(spacing: 16) {
            PerpsSheetTitle(title: "perpsMarketInfo".localized)
            PerpsCard {
                PerpsRow(title: "perpsFundingRate".localized,
                         subtitle: market.hourlyFunding >= 0 ? "perpsFundingLongsPay".localized : "perpsFundingShortsPay".localized,
                         value: String(format: "perpsPerHour".localized, PerpsFormat.percent(market.hourlyFunding * 100, digits: 4, signed: false)))
                PerpsRow(title: "perpsOpenInterest".localized, value: PerpsFormat.compactUsd(market.openInterestUsd), showsDivider: true)
                PerpsRow(title: "perpsDayVolume".localized, value: PerpsFormat.compactUsd(market.dayVolume), showsDivider: true)
                PerpsRow(title: "perpsMaxLeverage".localized, value: "\(market.maxLeverage)×", showsDivider: true)
            }
        }
        .perpsSheetChrome()
    }
}

/// Liquidation, explained with the position's own prices: a ladder from the
/// mark down (or up, for a short) to the liquidation price, then what happens
/// there, what the stop does first, and how margin moves it.
struct PerpsLiquidationSheet: View {
    let coin: String
    let isLong: Bool
    let mark: Decimal
    let entry: Decimal?
    let stopLoss: Decimal?
    let liquidation: Decimal?
    let onDone: () -> Void

    private enum Step: Hashable {
        case price(label: String, value: Decimal, color: Color, isLiquidation: Bool)
        case distance(String)
    }

    private var steps: [Step] {
        var prices: [Step] = [.price(label: String(format: "perpsCoinNow".localized, coin), value: mark,
                                     color: Theme.colors.textPrimary, isLiquidation: false)]
        if let entry {
            prices.append(.price(label: "perpsEntryTitle".localized, value: entry, color: Theme.colors.textSecondary, isLiquidation: false))
        }
        if let stopLoss {
            prices.append(.price(label: "perpsStopLoss".localized, value: stopLoss, color: Theme.colors.alertWarning, isLiquidation: false))
        }
        guard let liquidation else { return prices }
        let distance = PerpsMath.liquidationDistance(markPrice: mark, liquidationPrice: liquidation)
        let percent = PerpsFormat.percent(distance, digits: distance < 10 ? 1 : 0, signed: false)
        let tail: [Step] = [.distance(String(format: (isLong ? "perpsBelowNow" : "perpsAboveNow").localized, percent)),
                            .price(label: "perpsLiquidation".localized, value: liquidation, color: Theme.colors.alertError, isLiquidation: true)]
        // Highest price at the top: a long's liquidation sits under the mark, a short's above it.
        return isLong ? prices + tail : tail.reversed() + prices.reversed()
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                PerpsSheetTitle(title: "perpsLiquidation".localized)
                HStack {
                    Spacer()
                    PerpsSheetCloseButton(action: onDone)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(steps, id: \.self) { step in
                    switch step {
                    case let .price(label, value, color, isLiquidation):
                        HStack(spacing: 12) {
                            Circle()
                                .stroke(isLiquidation ? Theme.colors.alertError : color, lineWidth: 2)
                                .frame(width: 12, height: 12)
                            Text(label)
                                .font(Theme.fonts.bodySMedium)
                                .foregroundStyle(Theme.colors.textPrimary)
                            Spacer(minLength: 8)
                            Text(PerpsFormat.price(value))
                                .font(Theme.fonts.priceBodyS)
                                .monospacedDigit()
                                .foregroundStyle(color == Theme.colors.textSecondary ? Theme.colors.textPrimary : color)
                        }
                        .padding(.vertical, 8)
                    case let .distance(text):
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Theme.colors.alertError.opacity(0.6))
                                .frame(width: 2, height: 36)
                                .padding(.horizontal, 5)
                            Text(text)
                                .font(Theme.fonts.footnote)
                                .foregroundStyle(Theme.colors.textTertiary)
                        }
                    }
                }
                explanation
                    .padding(.top, 12)
            }
            .padding(PerpsLayout.cardPadding)
            .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface1))
            PrimaryButton(title: "perpsGotIt".localized, type: .secondary, action: onDone)
                .accessibilityIdentifier("perpsLiquidationGotIt")
        }
        .perpsSheetChrome()
    }

    /// "If BTC falls to $33,911, this trade closes on its own and you lose most
    /// of its margin." in full colour, then the stop and margin in grey.
    private var explanation: some View {
        let first = liquidation.map {
            String(format: (isLong ? "perpsLiquidationExplainFalls" : "perpsLiquidationExplainRises").localized, coin, PerpsFormat.price($0))
        } ?? ""
        var rest: [String] = []
        if let stopLoss, let liquidation {
            // Only a stop between the price and liquidation can act first.
            let placement = PerpsStopPlacement.of(stop: stopLoss, mark: mark, liquidation: liquidation, isLong: isLong)
            rest.append(String(format: placement.explainKey.localized, PerpsFormat.price(stopLoss)))
        }
        rest.append("perpsLiquidationExplainMargin".localized)
        return (Text(first).foregroundStyle(Theme.colors.textPrimary)
                + Text(" " + rest.joined(separator: " ")).foregroundStyle(Theme.colors.textTertiary))
            .font(Theme.fonts.bodySRegular)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
