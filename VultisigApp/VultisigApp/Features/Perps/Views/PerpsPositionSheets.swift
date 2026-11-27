//
//  PerpsPositionSheets.swift
//  VultisigApp
//
//  Perps position sheets: Close (25 / 50 / 100%), Modify (margin,
//  stop loss, take profit) with its Add / Remove margin page, and the
//  outcome of a position the venue closed. Each review goes through the
//  shared keysign review sheet; nothing here signs.
//

import SwiftUI

struct PerpsCloseSheet: View {
    let onReview: (PerpsReviewDocument) -> Void
    /// The screen's latest values: a sheet left open follows the poll.
    private let position: HLPosition
    private let market: PerpsMarket
    private let connection: PerpsConnection
    @StateObject private var viewModel: PerpsCloseViewModel

    init(position: HLPosition, market: PerpsMarket, fraction: PerpsCloseFraction = .all, vultTier: VultDiscountTier?,
         connection: PerpsConnection, onReview: @escaping (PerpsReviewDocument) -> Void) {
        self.onReview = onReview
        self.position = position
        self.market = market
        self.connection = connection
        _viewModel = StateObject(wrappedValue: PerpsCloseViewModel(position: position, market: market, fraction: fraction, vultTier: vultTier))
    }

    var body: some View {
        let coin = viewModel.market.coin
        let net = viewModel.netProfit
        let enabled = Set(PerpsCloseFraction.allCases.filter(viewModel.isAvailable))
        VStack(spacing: PerpsLayout.section) {
            PerpsSheetTitle(title: viewModel.title)
            PerpsChipPicker(selection: $viewModel.fraction, options: PerpsCloseFraction.allCases, title: \.title,
                            isEnabled: { enabled.contains($0) }, accessibilityPrefix: "perpsCloseFraction")
            VStack(spacing: 6) {
                Text(net >= 0 ? "perpsEstProfit".localized : "perpsEstLoss".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(PerpsFormat.usd(net, signed: true))
                    .font(Theme.fonts.priceLargeTitle)
                    .monospacedDigit()
                    .foregroundStyle(net >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                // The chip is a shortcut; this line is the lot-rounded truth.
                Text(String(format: "perpsClosingOf".localized, HLWireFormat.decimalString(viewModel.size),
                            PerpsCloseFlows.sizeText(viewModel.total, coin: coin)))
                    .font(Theme.fonts.priceFootnote)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            VStack(spacing: 10) {
                PerpsCard {
                    PerpsRow(title: "perpsBackToTradingAccount".localized, value: PerpsFormat.usd(viewModel.estimate.returned))
                    if viewModel.remaining > 0 {
                        PerpsRow(title: "perpsStillOpen".localized, value: PerpsCloseFlows.sizeText(viewModel.remaining, coin: coin),
                                 showsDivider: true)
                    }
                }
                PerpsFootnote(text: viewModel.issue ?? "perpsStopSlippageNote".localized, isError: viewModel.issue != nil)
            }
            PrimaryButton(title: "perpsReview".localized) {
                // Checked again at the tap: a tick can expire between renders.
                guard connection.isFresh() else { return viewModel.setPricesFresh(false) }
                guard let document = viewModel.reviewDocument() else { return }
                onReview(document)
            }
            .disabled(viewModel.issue != nil)
            .accessibilityIdentifier("perpsCloseReview")
        }
        .perpsSheetChrome()
        .onChange(of: PerpsSheetInputs(position: position, market: market)) { _, inputs in
            viewModel.refresh(position: inputs.position, market: inputs.market)
        }
        .background { PerpsFreshnessProbe(connection: connection) { viewModel.setPricesFresh($0) } }
    }
}

/// A quiet line under a card, red when it is the reason a CTA is disabled.
struct PerpsFootnote: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundStyle(isError ? Theme.colors.alertError : Theme.colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

// MARK: - Modify

/// One sheet. Margin drills into Add / Remove; stop loss
/// and take profit are edited inline, as on the stop loss sheet.
struct PerpsModifySheet: View {
    enum Page { case main, margin }

    let position: HLPosition
    let market: PerpsMarket
    let account: PerpsAccountSnapshot
    let triggers: [HLFrontendOrder]
    let vultTier: VultDiscountTier?
    let connection: PerpsConnection
    let onReview: (PerpsReviewDocument) -> Void
    let onClose: () -> Void

    @State private var page: Page
    @State private var triggerFocus: PerpsTriggerField?
    @StateObject private var exits: PerpsAutoCloseViewModel
    @StateObject private var margin: PerpsMarginViewModel

    init(position: HLPosition, market: PerpsMarket, account: PerpsAccountSnapshot, triggers: [HLFrontendOrder],
         vultTier: VultDiscountTier?, connection: PerpsConnection,
         startsOnMargin: Bool = false, marginRemoves: Bool = false, marginPrefill: Decimal? = nil,
         onReview: @escaping (PerpsReviewDocument) -> Void, onClose: @escaping () -> Void) {
        self.position = position
        self.market = market
        self.account = account
        self.triggers = triggers
        self.vultTier = vultTier
        self.connection = connection
        self.onReview = onReview
        self.onClose = onClose
        _page = State(initialValue: startsOnMargin ? .margin : .main)
        _exits = StateObject(wrappedValue: PerpsAutoCloseViewModel(
            side: position.isLong ? .long : .short, entry: position.entryPx?.value ?? market.markPrice, reference: market.markPrice,
            size: abs(position.szi.value), liquidation: position.liquidationPx?.value, szDecimals: market.szDecimals,
            takeProfit: triggers.first(where: \.isTakeProfit)?.triggerPx?.value,
            stopLoss: triggers.first(where: \.isStopLoss)?.triggerPx?.value
        ))
        _margin = StateObject(wrappedValue: PerpsMarginViewModel(position: position, market: market, account: account,
                                                                       isAdding: !marginRemoves, prefill: marginPrefill))
    }

    var body: some View {
        Group {
            switch page {
            case .main: mainPage
            case .margin:
                PerpsMarginPage(viewModel: margin, onBack: { page = .main }, onClose: onClose, onReview: { document in
                    guard connection.isFresh() else { return margin.setPricesFresh(false) }
                    onReview(document)
                })
            }
        }
        .perpsSheetChrome()
        // The screen polls every 15 s; both pages follow it while open.
        .onChange(of: PerpsSheetInputs(position: position, market: market, account: account, triggers: triggers)) { _, inputs in
            exits.refresh(PerpsExitInputs(position: inputs.position, market: inputs.market, triggers: inputs.triggers))
            if let account = inputs.account { margin.refresh(position: inputs.position, market: inputs.market, account: account) }
        }
        .background {
            PerpsFreshnessProbe(connection: connection) { isFresh in
                exits.setPricesFresh(isFresh)
                margin.setPricesFresh(isFresh)
            }
        }
    }

    private var mainPage: some View {
        VStack(spacing: 16) {
            ZStack {
                PerpsSheetTitle(title: "perpsModify".localized)
                HStack {
                    Spacer()
                    PerpsSheetCloseButton(action: onClose)
                        .accessibilityIdentifier("perpsModifyClose")
                }
            }
            PerpsCard {
                Button { page = .margin } label: {
                    PerpsRow(title: "perpsMargin".localized, value: PerpsFormat.usd(PerpsMarginFlows.margin(of: position))) { PerpsChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("perpsModifyMargin")
            }
            PerpsCard {
                PerpsTriggerRow(title: "perpsStopLoss".localized, text: exits.stopText, outcome: exits.outcome(exits.stopLoss),
                                placeholder: "perpsPricePlaceholder".localized, id: "perpsStopLossField", showsDivider: false,
                                isFocused: triggerFocus == .stopLoss) { triggerFocus = .stopLoss }
                PerpsTriggerRow(title: "perpsTakeProfit".localized, text: exits.takeText, outcome: exits.outcome(exits.takeProfit),
                                placeholder: "perpsOptional".localized, id: "perpsTakeProfitField", showsDivider: true,
                                isFocused: triggerFocus == .takeProfit) { triggerFocus = .takeProfit }
            }
            PerpsFootnote(text: exits.issue ?? "perpsStopSlippageNote".localized, isError: exits.issue != nil)
            PrimaryButton(title: "perpsReview".localized) {
                guard connection.isFresh() else { return exits.setPricesFresh(false) }
                // Real nonces only when the review is actually built.
                guard let document = exits.exitsReview(position: position, market: market, existing: triggers, tier: vultTier,
                                                      nonce: HyperliquidExchangeDryRunClient.shared.nonces.next(count: 2)) else { return }
                onReview(document)
            }
            .disabled(!exits.canReviewExits(position: position, market: market, existing: triggers, tier: vultTier))
            .accessibilityIdentifier("perpsModifyReview")
            if let triggerFocus {
                PerpsKeypad { exits.press($0, into: triggerFocus) }
            }
        }
    }
}

/// What an open position sheet follows: the poll's position, market, account and triggers.
struct PerpsSheetInputs: Hashable {
    let position: HLPosition
    let market: PerpsMarket
    var account: PerpsAccountSnapshot?
    var triggers: [HLFrontendOrder] = []
}

/// Feeds a sheet whether its prices may back a review: on appear, on every
/// connection change, and every 5 s so an expiring tick is noticed without a poll.
struct PerpsFreshnessProbe: View {
    @ObservedObject var connection: PerpsConnection
    let apply: (Bool) -> Void

    var body: some View {
        Color.clear
            .onAppear { apply(connection.isFresh()) }
            .onChange(of: connection.isOffline) { _, _ in apply(connection.isFresh()) }
            .onChange(of: connection.pricesAsOf) { _, _ in apply(connection.isFresh()) }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    apply(connection.isFresh())
                }
            }
    }
}

enum PerpsMarginDirection: Int, CaseIterable, Identifiable {
    case add, remove

    var id: Int { rawValue }
    var title: String { self == .add ? "perpsAdd".localized : "perpsRemove".localized }
}

struct PerpsMarginPage: View {
    @ObservedObject var viewModel: PerpsMarginViewModel
    let onBack: () -> Void
    let onClose: () -> Void
    let onReview: (PerpsReviewDocument) -> Void

    private var direction: Binding<PerpsMarginDirection> {
        Binding(get: { viewModel.isAdding ? .add : .remove }, set: { viewModel.isAdding = $0 == .add })
    }

    var body: some View {
        let change = viewModel.change
        VStack(spacing: PerpsLayout.section) {
            ZStack {
                PerpsSheetTitle(title: "perpsMargin".localized)
                HStack {
                    PerpsSheetBackButton(action: onBack)
                        .accessibilityIdentifier("perpsMarginBack")
                    Spacer()
                    PerpsSheetCloseButton(action: onClose)
                        .accessibilityIdentifier("perpsMarginClose")
                }
            }
            PerpsChipPicker(selection: direction, options: PerpsMarginDirection.allCases, title: \.title,
                            accessibilityPrefix: "perpsMarginDirection")
            VStack(spacing: 8) {
                // Same keypad as Withdraw: the decimal is always ".", whatever the locale.
                PerpsKeypadAmount(text: viewModel.amountText, accessibilityID: "perpsMarginAmount")
                // "Up to $6.20  Max" / "$149.81 available  Max": the limit stays visible, even when exceeded.
                HStack(spacing: 8) {
                    Text(viewModel.limitLine)
                        .font(Theme.fonts.bodySRegular)
                        .monospacedDigit()
                        .foregroundStyle(Theme.colors.textTertiary)
                    PrimaryButton(title: "perpsMax".localized, type: .secondary, size: .mini) { viewModel.applyMax() }
                        .fixedSize()
                        .accessibilityIdentifier("perpsMarginMax")
                }
            }
            VStack(spacing: 10) {
                PerpsCard {
                    if viewModel.issue == nil, viewModel.amount > 0 {
                        PerpsRow(title: "perpsMargin".localized,
                                 value: PerpsMarginFlows.arrow(PerpsFormat.usd(change.marginBefore), PerpsFormat.usd(change.marginAfter)))
                        PerpsRow(title: "perpsLiquidation".localized,
                                 value: PerpsMarginFlows.arrow(change.liquidationBefore.map(PerpsFormat.price) ?? "perpsNone".localized,
                                                               change.liquidationAfter.map(PerpsFormat.price) ?? "perpsNone".localized),
                                 showsDivider: true)
                    } else {
                        PerpsRow(title: "perpsMargin".localized, value: PerpsFormat.usd(change.marginBefore))
                    }
                }
                if let issue = viewModel.issue {
                    PerpsFootnote(text: issue, isError: true)
                        .accessibilityIdentifier("perpsMarginIssue")
                }
            }
            PrimaryButton(title: "perpsReview".localized) {
                guard let document = viewModel.reviewDocument() else { return }
                onReview(document)
            }
            .disabled(!viewModel.canReview)
            .accessibilityIdentifier("perpsMarginReview")
            PerpsKeypad { viewModel.amountText = PerpsKeypadKey.apply($0, to: viewModel.amountText) }
                .padding(.top, -12)
        }
    }
}

/// Price field with what the trigger would make or lose ("62,281  −$14.00").
struct PerpsTriggerRow: View {
    let title: String
    let text: String
    let outcome: Decimal?
    let placeholder: String
    let id: String
    let showsDivider: Bool
    var isFocused = false
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) { content }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if showsDivider { Separator(color: Theme.colors.borderLight, opacity: 1) }
            HStack(spacing: 10) {
                Text(title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .fixedSize()
                Spacer(minLength: 8)
                // "$63,900", like the stop loss row on the position screen,
                // grouped as it is typed on the "." keypad.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(text.isEmpty ? placeholder : "$" + PerpsInput.grouped(text))
                        .font(Theme.fonts.priceBodyL)
                        .monospacedDigit()
                        .foregroundStyle(text.isEmpty ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                        .fixedSize()
                    if isFocused {
                        PerpsCaret(height: 20)
                    }
                }
                .frame(minWidth: 96, alignment: .trailing)
                if let outcome {
                    Text(PerpsFormat.usd(outcome, signed: true))
                        .font(Theme.fonts.priceCaption)
                        .monospacedDigit()
                        .foregroundStyle(outcome >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Outcomes

/// What closed the position, the signed result, the fill,
/// what came back, Details, Done.
struct PerpsOutcomeSheet: View {
    let outcome: PerpsOutcome
    let onDone: () -> Void

    var body: some View {
        let side = outcome.isLong ? "perpsLong".localized : "perpsShort".localized
        PerpsResultSheet(
            caption: caption(side: side),
            title: PerpsFormat.usd(outcome.netPnl, signed: true),
            titleColor: outcome.netPnl >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError,
            titleIsAmount: true,
            message: message(side: side),
            details: details,
            actionTitle: "perpsDone".localized,
            action: onDone
        )
    }

    private func caption(side: String) -> String {
        switch outcome.kind {
        case .stopLoss: return "perpsStopLossHit".localized
        case .takeProfit: return "perpsTakeProfitHit".localized
        case .liquidated: return String(format: "perpsLiquidatedTitle".localized, outcome.coin, side)
        }
    }

    private func message(side: String) -> String {
        let fill = PerpsFormat.price(outcome.fillPrice)
        let first: String
        let second: String
        switch outcome.kind {
        case .stopLoss, .takeProfit:
            first = String(format: "perpsOutcomeClosedAt".localized, outcome.coin, side, fill)
            second = String(format: "perpsOutcomeBack".localized, PerpsFormat.usd(outcome.returned))
        case .liquidated:
            let move = outcome.isLong ? "perpsFellTo".localized : "perpsRoseTo".localized
            first = String(format: "perpsLiquidatedBody".localized, outcome.coin, move, fill, side)
            second = outcome.returned > 0
                ? String(format: "perpsLiquidatedBack".localized, PerpsFormat.usd(outcome.returned))
                : "perpsLiquidatedNothingBack".localized
        }
        return first + "\n" + second
    }

    private var details: [PerpsReviewRow] {
        var rows: [PerpsReviewRow] = []
        if let trigger = outcome.triggerPrice {
            rows.append(PerpsReviewRow(label: "perpsTriggerPrice".localized, value: PerpsFormat.price(trigger)))
        }
        rows.append(PerpsReviewRow(label: "perpsFilledAt".localized, value: PerpsFormat.price(outcome.fillPrice)))
        rows.append(PerpsReviewRow(label: "perpsFees".localized, value: PerpsFormat.usd(outcome.fees)))
        return rows
    }
}

/// The order did not fill. Nothing changed and nothing was charged.
struct PerpsOrderFailedSheet: View {
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        PerpsResultSheet(
            mark: .failure,
            title: "perpsOrderDidntFill".localized,
            message: "perpsOrderDidntFillBody".localized,
            actionTitle: "perpsTryAgain".localized,
            secondaryActionTitle: "perpsBack".localized,
            secondaryAction: onBack,
            action: onRetry
        )
    }
}
