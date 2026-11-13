//
//  PerpsPositionScreen.swift
//  VultisigApp
//
//  Perps position: P&L and return, the chart with entry and
//  liquidation lines, four tiles, the auto close row, then Modify / Close.
//

import SwiftUI

struct PerpsPositionScreen: View {
    let vault: Vault
    let coin: String

    private enum SheetKind: Identifiable, Equatable {
        case close(PerpsCloseFraction), modify(startsOnMargin: Bool), autoClose, stopNotPlaced, positionClosed, outcome(PerpsOutcome)
        case closing(Decimal), partlyClosed(PerpsPartialFill)
        var id: String {
            switch self {
            case .closing: return "closing"
            case .partlyClosed: return "partlyClosed"
            case .close: return "close"
            case .modify: return "modify"
            case .autoClose: return "autoClose"
            case .stopNotPlaced: return "stopNotPlaced"
            case .positionClosed: return "positionClosed"
            case .outcome: return "outcome"
            }
        }
    }

    @StateObject private var viewModel: PerpsMarketViewModel
    @State private var sheet: SheetKind?
    @State private var pendingReview: PerpsReviewDocument?
    @State private var pendingSheet: SheetKind?
    /// While an outcome is shown, the header shows the closed result, not the live P&L.
    @State private var outcome: PerpsOutcome?
    /// The same for a close the user made (net P&L, return on margin).
    @State private var closedByUser: ClosedResult?
    #if DEBUG
    /// Debug story: the review on screen is a close of the whole position.
    @State private var reviewClosesAll = false
    #endif
    @State private var didPresentReview = false

    private struct ClosedResult: Equatable {
        let pnl: Decimal
        let roe: Decimal
    }

    /// Set while a closed result is shown; the live rows and actions hide.
    private var closedResult: ClosedResult? {
        outcome.map { ClosedResult(pnl: $0.netPnl, roe: $0.returnOnMargin) } ?? closedByUser
    }
    /// Size a partly filled close already took off; the screen shows what is left.
    @State private var closedSize: Decimal = 0
    /// A close sent and not yet confirmed: shown as a "Closing…" row, and no
    /// second close is offered until the fill (or cancel) is reconciled.
    @State private var pendingClose: Decimal?
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter

    init(vault: Vault, coin: String) {
        self.vault = vault
        self.coin = coin
        _viewModel = StateObject(wrappedValue: PerpsMarketViewModel(coin: coin))
    }

    var body: some View {
        Screen {
            VStack(spacing: 12) {
                ScrollView(showsIndicators: false) {
                    if let position {
                        content(position)
                    }
                }
                if position != nil, closedResult == nil {
                    if isNearLiquidation {
                        // The two ways out when the position is at risk.
                        HStack(spacing: 10) {
                            PrimaryButton(title: "perpsClose".localized, type: .secondary) { sheet = .close(.all) }
                                .disabled(pendingClose != nil)
                                .accessibilityIdentifier("perpsClosePosition")
                            PrimaryButton(title: "perpsAddMargin".localized) { sheet = .modify(startsOnMargin: true) }
                                .accessibilityIdentifier("perpsAddMarginAction")
                        }
                    } else {
                        HStack(spacing: 10) {
                            PrimaryButton(title: "perpsModify".localized, type: .secondary) { sheet = .modify(startsOnMargin: false) }
                                .accessibilityIdentifier("perpsModify")
                            PrimaryButton(title: "perpsClose".localized) {
                                #if DEBUG
                                // Debug demo: Close shows the result a signed close would.
                                if PerpsDemoState.current.contains(.positionClosed) { return showPositionClosed() }
                                #endif
                                sheet = .close(.all)
                            }
                            .disabled(pendingClose != nil)
                            .accessibilityIdentifier("perpsClosePosition")
                        }
                    }
                }
            }
        }
        .perpsCompactHeader(coin: coin)
        .perpsScreenMargins()
        .task {
            await viewModel.load(vault: vault)
            #if DEBUG
            // Debug only: order results a dry run never produces.
            guard position != nil else { return }
            presentDemoState()
            #endif
        }
        // Debug story only: closing a full-close review stands in for signing it.
        .onChange(of: reviewPresenter.presented == nil) { _, isClosed in
            guard isClosed, didPresentReview else { return }
            didPresentReview = false
            #if DEBUG
            guard PerpsDemoStory.isOn, reviewClosesAll else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                showPositionClosed()
            }
            #endif
        }
        .crossPlatformSheet(item: $sheet, onDismiss: presentPendingReview) { kind in
            sheetContent(kind)
        }
    }

    /// The whole position closed at the mark: the header switches to the result.
    private func showPositionClosed() {
        guard let position, let market = viewModel.market else { return }
        let estimate = PerpsFlows.closeEstimate(position: position, market: market, size: abs(position.szi.value))
        let net = estimate.realizedPnl - estimate.fees
        let margin = PerpsMarginFlows.margin(of: position)
        closedByUser = ClosedResult(pnl: net, roe: margin > 0 ? net / margin : 0)
        sheet = .positionClosed
    }

    #if DEBUG
    /// Debug only: the sheets and outcomes a dry run never reaches.
    private func presentDemoState() {
        let state = PerpsDemoState.current
        if state.contains(.stopNotPlaced) { sheet = .stopNotPlaced }
        if state.contains(.modify) { sheet = .modify(startsOnMargin: false) }
        if state.contains(.addMargin) { sheet = .modify(startsOnMargin: true) }
        if state.contains(.closeHalf) { sheet = .close(.half) }
        if state.contains(.closeQuarter) { sheet = .close(.quarter) }
        if state.contains(.removeMarginBlocked) { sheet = .modify(startsOnMargin: true) }
        guard let position, let market = viewModel.market else { return }
        let quarter = PerpsCloseFraction.quarter.size(of: abs(position.szi.value), szDecimals: market.szDecimals)
        if state.contains(.closing) {
            pendingClose = quarter
            sheet = .closing(quarter)
        }
        if state.contains(.partlyClosed) {
            // A 25% close that filled about two thirds, a touch under the mark.
            let filled = HLWireFormat.size(quarter * (Decimal(string: "0.68") ?? 0), szDecimals: market.szDecimals)
            let price = PerpsFormat.roundedPrice(market.markPrice * (1 - (Decimal(string: "0.00008") ?? 0)))
            let fill = PerpsPartialFill.make(position: position, requested: quarter, filled: filled, fillPrice: price)
            closedSize = fill.filled
            sheet = .partlyClosed(fill)
        }
        let kind: PerpsOutcome.Kind? = state.contains(.stopLossHit) ? .stopLoss
            : state.contains(.takeProfitHit) ? .takeProfit
            : state.contains(.liquidated) ? .liquidated : nil
        if let kind {
            let result = PerpsDemoRepository.outcome(kind, position: position, triggers: viewModel.triggers, market: market)
            outcome = result
            sheet = .outcome(result)
        }
    }
    #endif

    /// Within 2% of the liquidation price, from live mark and position data.
    private var isNearLiquidation: Bool {
        guard closedResult == nil, let market = viewModel.market, let position else { return false }
        return PerpsMath.isNearLiquidation(markPrice: market.markPrice, liquidationPrice: position.liquidationPx?.value)
    }

    private func liquidationNotice(_ position: HLPosition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "perpsNearLiquidationTitle".localized, coin))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.alertError)
            Text(String(format: "perpsNearLiquidationBody".localized, coin,
                        viewModel.market.map { PerpsFormat.price($0.markPrice) } ?? "-",
                        position.liquidationPx.map { PerpsFormat.price($0.value) } ?? "-"))
                .font(Theme.fonts.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PerpsLayout.cardPadding)
        .background(Theme.radius.lg.shape.fill(Theme.colors.alertError.opacity(0.1)))
        .overlay(Theme.radius.lg.shape.stroke(Theme.colors.alertError.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("perpsNearLiquidation")
    }

    /// The venue's position, less what a partly filled close already took.
    private var position: HLPosition? {
        guard let position = viewModel.position else { return nil }
        return closedSize > 0 ? PerpsCloseFlows.remaining(after: closedSize, of: position) : position
    }

    private var stop: Decimal? { viewModel.triggers.first(where: \.isStopLoss)?.triggerPx?.value }
    private var take: Decimal? { viewModel.triggers.first(where: \.isTakeProfit)?.triggerPx?.value }

    private func content(_ position: HLPosition) -> some View {
        let live = PerpsFlows.livePnl(position: position, markPrice: viewModel.market?.markPrice)
        let pnl = closedResult?.pnl ?? live.pnl
        let roi = (closedResult?.roe ?? live.roe) * 100
        let tint = pnl >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError
        let sideLeverage = (position.isLong ? "perpsLongTitle".localized : "perpsShortTitle".localized) + " \(position.leverage.value)×"
        // "Long 2× · 0.00298 BTC", or "Closed · Long 2×" once the venue closed it.
        let side = closedResult == nil
            ? sideLeverage + " · \(HLWireFormat.decimalString(abs(position.szi.value))) \(coin)"
            : "perpsClosed".localized + " · " + sideLeverage
        return VStack(alignment: .leading, spacing: 16) {
            if isNearLiquidation { liquidationNotice(position) }
            VStack(alignment: .leading, spacing: 4) {
                Text(PerpsFormat.usd(pnl, signed: true))
                    .font(Theme.fonts.priceLargeTitle)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                // "+12.4% · Long 2× · 0.00299 BTC"
                HStack(spacing: 0) {
                    Text(PerpsFormat.percent(roi, digits: 1)).foregroundStyle(tint)
                    Text(" · " + side).foregroundStyle(Theme.colors.textTertiary)
                }
                .font(Theme.fonts.priceFootnote)
                .monospacedDigit()
            }
            // The line follows the position's P&L, not the price move over the window.
            PerpsPriceChart(points: viewModel.points, levels: levels(position), height: 200, tint: tint)
            // A closed position has no live rows: the outcome sheet carries the result.
            if closedResult == nil {
                if let pendingClose {
                    PerpsCard {
                        PerpsRow(title: "perpsClosingEllipsis".localized, value: PerpsCloseFlows.sizeText(pendingClose, coin: coin)) {
                            ProgressView().controlSize(.small).tint(Theme.colors.textTertiary)
                        }
                    }
                    .accessibilityIdentifier("perpsClosingRow")
                }
                PerpsCard {
                    PerpsRow(title: "perpsLiquidation".localized,
                             value: position.liquidationPx.map { PerpsFormat.price($0.value) } ?? "perpsNone".localized)
                    PerpsRow(title: "perpsEntryTitle".localized, value: position.entryPx.map { PerpsFormat.price($0.value) } ?? "-", showsDivider: true)
                    // "$99.94 isolated": the mode is a quiet suffix, not part of the amount.
                    PerpsRow(title: "perpsMargin".localized, value: PerpsFormat.usd(PerpsMarginFlows.margin(of: position)), showsDivider: true) {
                        Text(position.leverage.isCross ? "perpsCross".localized : "perpsIsolated".localized)
                            .font(Theme.fonts.footnote)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
                PerpsCard {
                    Button { sheet = .autoClose } label: {
                        PerpsRow(title: "perpsStopLoss".localized, value: stopLossValue) { PerpsChevron() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("perpsAutoCloseRow")
                }
                if let order = PerpsTriggerCoverage.uncovered(triggers: viewModel.triggers, positionSize: abs(position.szi.value)) {
                    PerpsFootnote(text: String(format: "perpsTriggerPartlyCovers".localized,
                                               PerpsCloseFlows.sizeText(order.sz.value, coin: coin),
                                               PerpsCloseFlows.sizeText(abs(position.szi.value), coin: coin)),
                                  isError: true)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    /// "Stop $150.00", "TP $201.00 · Stop $150.00" or "Off".
    private var stopLossValue: String { PerpsFlows.stopLossValue(stop) }

    private func levels(_ position: HLPosition) -> [PerpsLevel] {
        var levels: [PerpsLevel] = []
        if let entry = position.entryPx?.value {
            levels.append(PerpsLevel(title: "perpsEntryTitle".localized, price: entry, color: Theme.colors.textTertiary, isPinned: true))
        }
        if let liquidation = position.liquidationPx?.value {
            levels.append(PerpsLevel(title: "perpsLiquidation".localized, price: liquidation, color: Theme.colors.alertError))
        }
        return levels
    }

    @ViewBuilder
    private func sheetContent(_ kind: SheetKind) -> some View {
        if let position, let market = viewModel.market {
            switch kind {
            case .closing(let size):
                // Hide, not Close (ambiguous in a close flow). The row on the position stays.
                PerpsResultSheet(
                    mark: .pending,
                    title: String(format: "perpsClosingSize".localized, PerpsCloseFlows.sizeText(size, coin: coin)),
                    message: "perpsUsuallyFewSeconds".localized,
                    actionTitle: "perpsHide".localized,
                    actionType: .secondary
                ) { sheet = nil }
            case .partlyClosed(let fill):
                partlyClosedSheet(fill, position: position, market: market)
            case .close(let fraction):
                PerpsCloseSheet(position: position, market: market, fraction: fraction, onReview: handOff)
            case .modify(let startsOnMargin):
                if let account = viewModel.account {
                    PerpsModifySheet(position: position, market: market, account: account, triggers: viewModel.triggers,
                                     startsOnMargin: startsOnMargin, marginRemoves: startsOnMargin && demoMarginRemoves,
                                     marginPrefill: demoMarginPrefill(startsOnMargin: startsOnMargin),
                                     onReview: handOff, onClose: { sheet = nil })
                }
            case .outcome(let result):
                PerpsOutcomeSheet(outcome: result) {
                    sheet = nil
                    outcome = nil
                }
            case .positionClosed:
                let estimate = PerpsFlows.closeEstimate(position: position, market: market, size: abs(position.szi.value))
                let back = estimate.returned
                // Net of the closing fee, like the close sheet's "Est. profit".
                let net = estimate.realizedPnl - estimate.fees
                PerpsResultSheet(
                    caption: String(format: "perpsPositionClosedTitle".localized, coin),
                    title: PerpsFormat.usd(net, signed: true),
                    titleColor: net >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError,
                    titleIsAmount: true,
                    message: String(format: "perpsOutcomeBack".localized, PerpsFormat.usd(back)),
                    details: [
                        PerpsReviewRow(label: "perpsClosedAt".localized, value: PerpsFormat.price(estimate.price)),
                        PerpsReviewRow(label: "perpsFees".localized, value: PerpsFormat.usd(estimate.fees))
                    ],
                    actionTitle: "perpsDone".localized
                ) {
                    sheet = nil
                    closedByUser = nil
                }
            case .stopNotPlaced:
                PerpsStatusSheet(
                    title: "perpsStopNotPlacedTitle".localized,
                    message: String(format: "perpsStopNotPlacedBody".localized, coin,
                                    position.isLong ? "perpsLong".localized : "perpsShort".localized),
                    row: PerpsReviewRow(label: "perpsStopLoss".localized, value: stop.map(PerpsFormat.price) ?? "perpsNone".localized),
                    actionTitle: "perpsSetStopLoss".localized
                ) {
                    pendingSheet = .autoClose
                    sheet = nil
                }
            case .autoClose:
                PerpsAutoCloseSheet(viewModel: PerpsAutoCloseViewModel(
                    side: position.isLong ? .long : .short, entry: position.entryPx?.value ?? market.markPrice, reference: market.markPrice,
                    size: abs(position.szi.value), liquidation: position.liquidationPx?.value, takeProfit: take, stopLoss: stop
                )) { newTake, newStop in
                    let document = try? PerpsFlows.editExits(position: position, market: market, existing: viewModel.triggers,
                                                             stopLoss: newStop, takeProfit: newTake,
                                                             nonce: HyperliquidExchangeDryRunClient.shared.nonces.next())
                    if let document, document.blockingIssue == nil { pendingReview = document }
                    sheet = nil
                }
            }
        }
    }

    /// Debug only: the demo top-up and the too-large removal.
    private func demoMarginPrefill(startsOnMargin: Bool) -> Decimal? {
        #if DEBUG
        guard startsOnMargin else { return nil }
        let state = PerpsDemoState.current
        if state.contains(.addMargin) { return PerpsDemoRepository.demoMarginAdd }
        if state.contains(.removeMarginBlocked) { return PerpsDemoRepository.demoMarginRemove }
        #endif
        return nil
    }

    private var demoMarginRemoves: Bool {
        #if DEBUG
        PerpsDemoState.current.contains(.removeMarginBlocked)
        #else
        false
        #endif
    }

    /// profit on the part that filled (net of the closing fee only), then what closed,
    /// what did not, what is still open and what came back. "Close 0.00024 BTC"
    /// opens the normal review with a fresh quote; it never sends by itself.
    private func partlyClosedSheet(_ fill: PerpsPartialFill, position: HLPosition, market: PerpsMarket) -> some View {
        PerpsResultSheet(
            caption: fill.netPnl >= 0 ? "perpsPartlyClosedProfit".localized : "perpsPartlyClosedLoss".localized,
            title: PerpsFormat.usd(fill.netPnl, signed: true),
            titleColor: fill.netPnl >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError,
            titleIsAmount: true,
            message: String(format: "perpsClosedAtPrice".localized, PerpsFormat.price(fill.fillPrice)),
            statusRows: [
                PerpsReviewRow(label: "perpsClosed".localized, value: PerpsCloseFlows.sizeText(fill.filled, coin: coin, szDecimals: market.szDecimals)),
                PerpsReviewRow(label: "perpsDidntClose".localized, value: PerpsCloseFlows.sizeText(fill.notClosed, coin: coin, szDecimals: market.szDecimals)),
                PerpsReviewRow(label: "perpsStillOpen".localized, value: PerpsCloseFlows.sizeText(fill.stillOpen, coin: coin, szDecimals: market.szDecimals)),
                PerpsReviewRow(label: "perpsBackToTradingAccount".localized, value: PerpsFormat.usd(fill.returned))
            ],
            note: "perpsRestDidntFill".localized,
            actionTitle: String(format: "perpsCloseAmount".localized, PerpsCloseFlows.sizeText(fill.notClosed, coin: coin, szDecimals: market.szDecimals)),
            secondaryActionTitle: "perpsDone".localized,
            secondaryAction: { sheet = nil },
            action: {
                guard let document = try? PerpsFlows.partialClose(position: position, market: market, size: fill.notClosed,
                                                                  nonce: HyperliquidExchangeDryRunClient.shared.nonces.next()) else { return }
                handOff(document)
            }
        )
    }

    private func handOff(_ document: PerpsReviewDocument) {
        #if DEBUG
        // Debug story: a review titled by the whole size closes the position.
        if let position {
            reviewClosesAll = document.amountLabel == String(format: "perpsCloseAmount".localized,
                                                             PerpsCloseFlows.sizeText(abs(position.szi.value), coin: coin))
        }
        #endif
        pendingReview = document
        sheet = nil
    }

    private func presentPendingReview() {
        if let next = pendingSheet {
            pendingSheet = nil
            sheet = next
            return
        }
        guard let document = pendingReview else { return }
        pendingReview = nil
        didPresentReview = true
        reviewPresenter.present(.perps(request: PerpsReviewRequest(document: document), vaultPubKeyECDSA: vault.pubKeyECDSA))
    }
}

/// Debug only: every body the dry-run client would have posted, newest first.
struct PerpsDryRunLogScreen: View {
    @ObservedObject private var client = HyperliquidExchangeDryRunClient.shared

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(client.log) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.kind).font(Theme.fonts.bodySMedium).foregroundStyle(Theme.colors.textPrimary)
                            Text(entry.json)
                                .font(Theme.fonts.caption10)
                                .foregroundStyle(Theme.colors.textSecondary)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.radius.md.shape.fill(Theme.colors.bgSurface1))
                    }
                }
            }
        }
        .screenTitle("Dry run")
    }
}
