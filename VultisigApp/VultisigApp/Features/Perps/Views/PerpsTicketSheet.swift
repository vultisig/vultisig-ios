//
//  PerpsTicketSheet.swift
//  VultisigApp
//
//  Perps ticket: "Long BTC", the margin, "$X available", then
//  three rows (leverage, size, stop loss) and one Review. Leverage and stop
//  loss open their own small sheets.
//

import SwiftUI

struct PerpsTicketSheet: View {
    let onReview: (PerpsReviewDocument) -> Void

    private enum SubSheet: Identifiable {
        case leverage, autoClose, addFunds
        var id: Self { self }
    }

    @StateObject private var viewModel: PerpsTicketViewModel
    @ObservedObject private var connection: PerpsConnection
    @State private var subSheet: SubSheet?

    init(side: PerpsSide, market: PerpsMarket, account: PerpsAccountSnapshot?, vault: PerpsVaultContext,
         connection: PerpsConnection, onReview: @escaping (PerpsReviewDocument) -> Void) {
        self.onReview = onReview
        self.connection = connection
        _viewModel = StateObject(wrappedValue: PerpsTicketViewModel(side: side, market: market, account: account, vault: vault))
    }

    var body: some View {
        VStack(spacing: PerpsLayout.section) {
            PerpsSheetTitle(title: viewModel.title)
            VStack(spacing: 6) {
                Text("perpsMargin".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                PerpsAmountInput(text: $viewModel.amountText, accessibilityID: "perpsTicketAmount")
                Text(viewModel.summaryLine)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                if let issue = viewModel.issue, viewModel.fundingShortfall == nil {
                    Text(issue)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.alertError)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("perpsTicketIssue")
                }
            }
            PerpsCard {
                Button { subSheet = .leverage } label: {
                    PerpsRow(title: "perpsLeverage".localized, value: "\(viewModel.leverage)×") { PerpsChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("perpsLeverageRow")
                Button { viewModel.showsSizeInCoin.toggle() } label: {
                    PerpsRow(title: "perpsPositionSize".localized, value: viewModel.sizeText, showsDivider: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("perpsSizeRow")
                Button { subSheet = .autoClose } label: {
                    PerpsRow(title: "perpsStopLoss".localized, value: viewModel.stopLossValue, showsDivider: true) { PerpsChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("perpsAutoCloseRow")
            }
            if connection.isOffline {
                // The draft stays; Review comes back after a reconnect refreshed the quote.
                VStack(spacing: 10) {
                    PerpsOfflineBanner(minutes: connection.minutesStale())
                    PrimaryButton(title: "perpsReconnecting".localized) {}
                        .disabled(true)
                        .accessibilityIdentifier("perpsReconnecting")
                }
            } else if viewModel.fundingShortfall != nil {
                // The shortfall once, right above the action that fixes it.
                // Add funds opens over the ticket, so the draft stays as it is.
                VStack(spacing: 8) {
                    if let message = viewModel.shortfallMessage {
                        Text(message)
                            .font(Theme.fonts.subtitle)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .accessibilityIdentifier("perpsTicketShortfall")
                    }
                    PrimaryButton(title: "perpsAddFunds".localized) { subSheet = .addFunds }
                        .accessibilityIdentifier("perpsTicketAddFunds")
                }
            } else {
                PrimaryButton(title: "perpsReview".localized) {
                    guard let document = viewModel.reviewDocument() else { return }
                    onReview(document)
                }
                .disabled(!viewModel.canReview)
                .accessibilityIdentifier("perpsReviewButton")
            }
        }
        .perpsSheetChrome()
        .task(id: connection.isOffline) {
            // Retry every few seconds while offline.
            while connection.isOffline, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await connection.reconnect()
            }
        }
        .onChange(of: connection.isOffline) { _, isOffline in
            guard !isOffline, let market = connection.market else { return }
            viewModel.refresh(market: market, account: connection.account)
        }
        .crossPlatformSheet(item: $subSheet) { kind in
            switch kind {
            case .leverage:
                PerpsLeverageSheet(selected: viewModel.leverage, options: viewModel.leverageOptions,
                                   maxAllowed: viewModel.maxAllowedLeverage, marketMax: viewModel.market.maxLeverage) { value in
                    viewModel.leverage = value
                    subSheet = nil
                }
            case .addFunds:
                PerpsFundsSheet(account: viewModel.account, vault: viewModel.vault, prefill: viewModel.fundingShortfall) { document in
                    subSheet = nil
                    onReview(document)
                }
            case .autoClose:
                PerpsAutoCloseSheet(viewModel: PerpsAutoCloseViewModel(
                    side: viewModel.side, entry: viewModel.referencePrice, reference: viewModel.referencePrice,
                    size: viewModel.estimate?.size ?? 0, liquidation: viewModel.estimate?.liquidationPrice,
                    szDecimals: viewModel.market.szDecimals,
                    takeProfit: viewModel.takeProfit, stopLoss: viewModel.stopLoss
                )) { take, stop in
                    viewModel.applyAutoClose(takeProfit: take, stopLoss: stop)
                    subSheet = nil
                }
            }
        }
    }
}

/// "Can't connect. Prices are from 2 min ago.": the app's warning banner.
struct PerpsOfflineBanner: View {
    let message: String

    init(minutes: Int) {
        message = String(format: "perpsCantConnect".localized, minutes)
    }

    init(message: String) {
        self.message = message
    }

    var body: some View {
        InfoBannerView(description: message, type: .warning, leadingIcon: .triangleWarning)
            .accessibilityIdentifier("perpsOfflineBanner")
    }
}

/// Leverage chips; anything above the first-trade cap is shown but disabled.
struct PerpsLeverageSheet: View {
    let selected: Int
    let options: [Int]
    let maxAllowed: Int
    let marketMax: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 20) {
            PerpsSheetTitle(title: "perpsLeverage".localized)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { value in
                    Button { onSelect(value) } label: {
                        Text("\(value)×")
                            .font(Theme.fonts.priceBodyL)
                            .foregroundStyle(value == selected ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(value == selected ? Theme.colors.primaryAccent3 : Theme.colors.bgSurface2))
                    }
                    .buttonStyle(.plain)
                    .disabled(value > maxAllowed)
                    .opacity(value > maxAllowed ? 0.35 : 1)
                    .accessibilityIdentifier("perpsLeverage-\(value)")
                }
            }
            if maxAllowed < marketMax {
                Text(String(format: "perpsFirstTradeCap".localized, maxAllowed))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .perpsSheetChrome()
    }
}

/// take profit and stop loss rows with what each would make or lose.
struct PerpsAutoCloseSheet: View {
    @StateObject private var viewModel: PerpsAutoCloseViewModel
    let onDone: (Decimal?, Decimal?) -> Void

    init(viewModel: PerpsAutoCloseViewModel, onDone: @escaping (Decimal?, Decimal?) -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 16) {
            PerpsSheetTitle(title: "perpsStopLoss".localized)
            PerpsCard {
                // The stop first, take profit second and optional.
                PerpsTriggerRow(title: "perpsStopLoss".localized, text: $viewModel.stopText, outcome: viewModel.outcome(viewModel.stopLoss),
                           placeholder: "perpsPricePlaceholder".localized, id: "perpsStopLossField", showsDivider: false)
                PerpsTriggerRow(title: "perpsTakeProfit".localized, text: $viewModel.takeText, outcome: viewModel.outcome(viewModel.takeProfit),
                           placeholder: "perpsOptional".localized, id: "perpsTakeProfitField", showsDivider: true)
            }
            Text(viewModel.issue ?? "perpsStopSlippageNote".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(viewModel.issue == nil ? Theme.colors.textTertiary : Theme.colors.alertError)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            PrimaryButton(title: "perpsDone".localized) { onDone(viewModel.takeProfit, viewModel.stopLoss) }
                .disabled(viewModel.issue != nil)
                .accessibilityIdentifier("perpsAutoCloseDone")
        }
        .perpsSheetChrome()
    }
}
