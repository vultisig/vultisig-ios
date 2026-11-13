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
