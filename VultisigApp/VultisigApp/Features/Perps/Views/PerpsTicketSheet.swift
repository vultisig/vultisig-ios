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
    @State private var showsKeypad = false
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
                PerpsAmountInput(text: viewModel.amountText, isFocused: showsKeypad, accessibilityID: "perpsTicketAmount") {
                    showsKeypad = true
                }
                Text(viewModel.summaryLine)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                PerpsQuickPicks(titles: ["25%", "50%", "perpsMax".localized]) { index in
                    switch index {
                    case 0: viewModel.applyFraction(Decimal(string: "0.25") ?? 0)
                    case 1: viewModel.applyFraction(Decimal(string: "0.5") ?? 0)
                    default: viewModel.applyMax()
                    }
                }
                .padding(.top, 4)
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
            if showsKeypad {
                PerpsKeypad { viewModel.amountText = PerpsKeypadKey.apply($0, to: viewModel.amountText) }
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
        // The screen behind refreshes prices every few seconds; a ticket left
        // open follows them, so the review never quotes an old mark.
        .onChange(of: connection.pricesAsOf) { _, _ in
            guard !connection.isOffline, let market = connection.market else { return }
            viewModel.refresh(market: market, account: connection.account)
        }
        .crossPlatformSheet(item: $subSheet) { kind in
            switch kind {
            case .leverage:
                PerpsLeverageSheet(coin: viewModel.market.coin, side: viewModel.side, selected: viewModel.leverage,
                                   options: viewModel.leverageOptions, maxAllowed: viewModel.maxAllowedLeverage,
                                   marketMax: viewModel.market.maxLeverage, referencePrice: viewModel.referencePrice,
                                   preview: viewModel.preview(leverage:), onBack: { subSheet = nil },
                                   onDone: { value in
                                       viewModel.leverage = value
                                       subSheet = nil
                                   })
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
                ), coin: viewModel.market.coin) { take, stop in
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

/// Leverage: the big value, a slider with evenly spaced stops (1/2/3/5/10/20/40×,
/// capped at the market's max), and the position size and liquidation it
/// would give, live. Stops above the first-trade cap show but do not take.
struct PerpsLeverageSheet: View {
    let coin: String
    let side: PerpsSide
    let options: [Int]
    let maxAllowed: Int
    let marketMax: Int
    let referencePrice: Decimal
    let preview: (Int) -> (size: Decimal, liquidation: Decimal?)
    let onBack: () -> Void
    let onDone: (Int) -> Void

    @State private var index: Int

    init(coin: String, side: PerpsSide, selected: Int, options: [Int], maxAllowed: Int, marketMax: Int, referencePrice: Decimal,
         preview: @escaping (Int) -> (size: Decimal, liquidation: Decimal?), onBack: @escaping () -> Void, onDone: @escaping (Int) -> Void) {
        self.coin = coin
        self.side = side
        self.options = options
        self.maxAllowed = maxAllowed
        self.marketMax = marketMax
        self.referencePrice = referencePrice
        self.preview = preview
        self.onBack = onBack
        self.onDone = onDone
        _index = State(initialValue: options.firstIndex(of: selected) ?? 0)
    }

    private var value: Int { options[min(index, options.count - 1)] }
    private var maxIndex: Int { options.lastIndex { $0 <= maxAllowed } ?? 0 }

    var body: some View {
        let live = preview(value)
        VStack(spacing: 20) {
            ZStack {
                PerpsSheetTitle(title: "perpsLeverage".localized)
                HStack {
                    PerpsSheetBackButton(action: onBack)
                    Spacer()
                }
            }
            VStack(spacing: 6) {
                Text("\(value)×")
                    .font(Theme.fonts.priceLargeTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.colors.textPrimary)
                    .accessibilityIdentifier("perpsLeverageValue")
                Text(maxAllowed < marketMax
                     ? String(format: "perpsFirstTradeCap".localized, maxAllowed)
                     : String(format: "perpsUpToOnCoin".localized, "\(marketMax)×", coin))
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            PerpsStopSlider(labels: options.map { "\($0)×" }, index: $index, maxIndex: maxIndex)
            PerpsCard {
                PerpsRow(title: "perpsPositionSize".localized, value: PerpsFormat.usd(live.size))
                PerpsRow(title: "perpsLiquidationPrice".localized, value: live.liquidation.map(PerpsFormat.price) ?? "-", showsDivider: true) {
                    if let distance = PerpsFormat.liquidationDistance(price: referencePrice, liquidation: live.liquidation, isLong: side == .long) {
                        Text(distance)
                            .font(Theme.fonts.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
            }
            PrimaryButton(title: "perpsDone".localized) { onDone(value) }
                .accessibilityIdentifier("perpsLeverageDone")
        }
        .perpsSheetChrome()
    }
}

/// A slider that snaps to evenly spaced stops, each label centred under its
/// dot. Stops past `maxIndex` are drawn dimmed and cannot be selected.
struct PerpsStopSlider: View {
    let labels: [String]
    @Binding var index: Int
    let maxIndex: Int

    private let thumb: CGFloat = 26

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width - thumb
                let step = labels.count > 1 ? width / CGFloat(labels.count - 1) : 0
                let x = thumb / 2 + step * CGFloat(index)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.colors.bgSurface2)
                        .frame(height: 4)
                        .padding(.horizontal, thumb / 2)
                    Capsule()
                        .fill(Theme.colors.primaryAccent4)
                        .frame(width: max(0, x - thumb / 2), height: 4)
                        .offset(x: thumb / 2)
                    ForEach(labels.indices, id: \.self) { stop in
                        Circle()
                            .fill(stop <= index ? Theme.colors.primaryAccent4 : Theme.colors.textTertiary)
                            .frame(width: 6, height: 6)
                            .opacity(stop > maxIndex ? 0.35 : 1)
                            .position(x: thumb / 2 + step * CGFloat(stop), y: thumb / 2)
                    }
                    Circle()
                        .fill(Theme.colors.textPrimary)
                        .frame(width: thumb, height: thumb)
                        .position(x: x, y: thumb / 2)
                }
                .frame(height: thumb)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    guard step > 0 else { return }
                    let nearest = Int(((drag.location.x - thumb / 2) / step).rounded())
                    index = min(max(0, nearest), maxIndex)
                })
            }
            .frame(height: thumb)
            // Labels centred on their stops.
            GeometryReader { geometry in
                let width = geometry.size.width - thumb
                let step = labels.count > 1 ? width / CGFloat(labels.count - 1) : 0
                ForEach(labels.indices, id: \.self) { stop in
                    Button { if stop <= maxIndex { index = stop } } label: {
                        Text(labels[stop])
                            .font(Theme.fonts.caption12)
                            .monospacedDigit()
                            .foregroundStyle(stop == index ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                            .opacity(stop > maxIndex ? 0.35 : 1)
                            .fixedSize()
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("perpsLeverage-\(labels[stop])")
                    .position(x: thumb / 2 + step * CGFloat(stop), y: 16)
                }
            }
            .frame(height: 32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("perpsLeverageSlider")
    }
}

/// take profit and stop loss rows with what each would make or lose.
struct PerpsAutoCloseSheet: View {
    @StateObject private var viewModel: PerpsAutoCloseViewModel
    @State private var focus: PerpsTriggerField?
    let coin: String
    let onDone: (Decimal?, Decimal?) -> Void

    init(viewModel: PerpsAutoCloseViewModel, coin: String, onDone: @escaping (Decimal?, Decimal?) -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coin = coin
        self.onDone = onDone
    }

    /// "Close if BTC drops" 5% / 7% / 10% / 25%, one tap each.
    private var stopPresets: some View {
        VStack(spacing: 8) {
            Text(String(format: (viewModel.side == .long ? "perpsCloseIfDrops" : "perpsCloseIfRises").localized, coin))
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
            let titles = PerpsAutoCloseViewModel.stopPresets.map { PerpsFormat.percent($0, digits: 0, signed: false) }
            PerpsQuickPicks(titles: titles,
                            selected: viewModel.selectedStopPreset.map { PerpsFormat.percent($0, digits: 0, signed: false) },
                            onPick: { viewModel.applyStopPreset(PerpsAutoCloseViewModel.stopPresets[$0]) },
                            accessibilityPrefix: "perpsStopPreset")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            PerpsSheetTitle(title: "perpsStopLoss".localized)
            stopPresets
            PerpsCard {
                // The stop first, take profit second and optional.
                PerpsTriggerRow(title: "perpsStopLoss".localized, text: viewModel.stopText, outcome: viewModel.outcome(viewModel.stopLoss),
                                placeholder: "perpsPricePlaceholder".localized, id: "perpsStopLossField", showsDivider: false,
                                isFocused: focus == .stopLoss) { focus = .stopLoss }
                PerpsTriggerRow(title: "perpsTakeProfit".localized, text: viewModel.takeText, outcome: viewModel.outcome(viewModel.takeProfit),
                                placeholder: "perpsOptional".localized, id: "perpsTakeProfitField", showsDivider: true,
                                isFocused: focus == .takeProfit) { focus = .takeProfit }
            }
            Text(viewModel.issue ?? "perpsStopSlippageNote".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(viewModel.issue == nil ? Theme.colors.textTertiary : Theme.colors.alertError)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            PrimaryButton(title: "perpsDone".localized) { onDone(viewModel.takeProfit, viewModel.stopLoss) }
                .disabled(viewModel.issue != nil)
                .accessibilityIdentifier("perpsAutoCloseDone")
            if let focus {
                PerpsKeypad { viewModel.press($0, into: focus) }
            }
        }
        .perpsSheetChrome()
    }
}
