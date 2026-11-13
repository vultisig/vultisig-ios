//
//  PerpsMarketScreen.swift
//  VultisigApp
//
//  Perps market: price and today's move, the chart with its
//  timeframes, what is available to trade, and Long / Short. Funding, open
//  interest and volume are one tap away under "Market info".
//

import SwiftUI

struct PerpsMarketScreen: View {
    let vault: Vault
    let coin: String

    private enum SheetKind: Identifiable, Equatable {
        case ticket(PerpsSide), addFunds, info, tradeOpened, orderFailed
        var id: String {
            switch self {
            case .orderFailed: return "orderFailed"
            case .ticket(let side): return "ticket-\(side.rawValue)"
            case .addFunds: return "addFunds"
            case .info: return "info"
            case .tradeOpened: return "tradeOpened"
            }
        }
    }

    @StateObject private var viewModel: PerpsMarketViewModel
    @State private var sheet: SheetKind?
    @State private var pendingReview: PerpsReviewDocument?
    @State private var didPresentReview = false
    @State private var pendingSheet: SheetKind?
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter
    @Environment(\.router) private var router

    init(vault: Vault, coin: String) {
        self.vault = vault
        self.coin = coin
        _viewModel = StateObject(wrappedValue: PerpsMarketViewModel(coin: coin))
    }

    var body: some View {
        Screen {
            VStack(spacing: 12) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.market == nil {
                            PerpsMarketUnavailableBanner(connection: viewModel.connection)
                        }
                        header
                        PerpsPriceChart(points: viewModel.points, height: 240)
                            .opacity(viewModel.isLoadingChart ? 0.4 : 1)
                        PerpsTimeframePicker(selected: viewModel.timeframe, onSelect: viewModel.select)
                        accountCard
                    }
                    .padding(.top, 4)
                }
                HStack(spacing: 10) {
                    PrimaryButton(title: "perpsLongTitle".localized, type: .primary) { sheet = .ticket(.long) }
                        .accessibilityIdentifier("perpsLongButton")
                    PrimaryButton(title: "perpsShortTitle".localized, type: .secondary) { sheet = .ticket(.short) }
                        .accessibilityIdentifier("perpsShortButton")
                }
                .disabled(viewModel.market == nil)
            }
        }
        .perpsCompactHeader(coin: coin)
        .perpsScreenMargins()
        .task {
            await viewModel.load(vault: vault)
            #if DEBUG
            // Debug only: a fill a dry run can never miss.
            if PerpsDemoState.current.contains(.orderFailed) { sheet = .orderFailed }
            if PerpsDemoState.current.contains(.offline) { sheet = .ticket(.long) }
            #endif
        }
        // Debug only: after a review closes, show the result a signed order would.
        .onChange(of: reviewPresenter.presented == nil) { _, isClosed in
            guard isClosed, didPresentReview else { return }
            didPresentReview = false
            #if DEBUG
            let story = PerpsDemoStory.isOn && PerpsDemoStory.stage == .funded
            guard PerpsDemoState.current.contains(.tradeOpened) || story else { return }
            Task { @MainActor in
                if story {
                    // Debug story: the order "filled" at the ticket's price.
                    PerpsDemoStory.stage = .opened
                    await viewModel.load(vault: vault)
                }
                // Let the review finish leaving before the next sheet rises.
                try? await Task.sleep(for: .milliseconds(500))
                sheet = .tradeOpened
            }
            #endif
        }
        // The review is the shared keysign review sheet, hosted at the root, so
        // the input sheet closes first and the review opens once it is gone.
        .crossPlatformSheet(item: $sheet, onDismiss: presentPendingReview) { kind in
            sheetContent(kind)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.market.map { PerpsFormat.price($0.markPrice) } ?? " ")
                .font(Theme.fonts.priceLargeTitle)
                .monospacedDigit()
                .foregroundStyle(Theme.colors.textPrimary)
                .contentTransition(.numericText())
            if let change = viewModel.dayChange {
                // One quiet line: "+$731.50 · +1.10%".
                Text("\(PerpsFormat.usd(change.amount, signed: true)) · \(PerpsFormat.percent(change.percent))")
                    .font(Theme.fonts.priceFootnote)
                    .monospacedDigit()
                    .foregroundStyle(change.amount >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError)
            }
        }
    }

    private var accountCard: some View {
        PerpsCard {
            if viewModel.position != nil {
                Button { router.navigate(to: PerpsRoute.position(vault: vault, coin: coin)) } label: {
                    PerpsRow(title: "perpsYourPosition".localized, value: viewModel.position.map {
                        PerpsFormat.usd(PerpsFlows.livePnl(position: $0, markPrice: viewModel.market?.markPrice).pnl, signed: true)
                    }) {
                        PerpsChevron()
                    }
                }
                .buttonStyle(.plain)
                Separator(color: Theme.colors.borderLight, opacity: 1)
            }
            Button { sheet = .addFunds } label: {
                // No value until the account loads: never a made-up "$0.00".
                PerpsRow(title: "perpsAvailableToTrade".localized, value: viewModel.account.map { PerpsFormat.usd($0.availableToTrade) }) {
                    Icon(.plus, color: Theme.colors.textPrimary, size: 14)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.colors.bgSurface2))
                    // The whole row is the button, so the tap target is the full 48pt row.
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perpsAvailableAddFunds")
            Separator(color: Theme.colors.borderLight, opacity: 1)
            Button { sheet = .info } label: {
                PerpsRow(title: "perpsMarketInfo".localized, value: nil) { PerpsChevron() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perpsMarketInfo")
        }
    }

    @ViewBuilder
    private func sheetContent(_ kind: SheetKind) -> some View {
        switch kind {
        case .ticket(let side):
            if let market = viewModel.market {
                PerpsTicketSheet(side: side, market: market, account: viewModel.account, vault: PerpsVaultContext(vault: vault),
                                 connection: viewModel.connection, onReview: handOff)
            }
        case .addFunds:
            PerpsFundsSheet(account: viewModel.account, vault: PerpsVaultContext(vault: vault), onReview: handOff)
        case .orderFailed:
            PerpsOrderFailedSheet(
                onRetry: {
                    pendingSheet = .ticket(.long)
                    sheet = nil
                },
                onBack: { sheet = nil }
            )
        case .info:
            if let market = viewModel.market { PerpsMarketInfoSheet(market: market) }
        case .tradeOpened:
            if let market = viewModel.market {
                // Same entry the position screen shows.
                let entry = viewModel.position?.entryPx?.value ?? market.markPrice
                let side = (viewModel.position?.isLong ?? true) ? "perpsLong".localized : "perpsShort".localized
                PerpsResultSheet(
                    mark: .success,
                    title: String(format: "perpsTradeOpenedTitle".localized, coin, side),
                    message: String(format: "perpsOpenedAt".localized, PerpsFormat.price(entry)),
                    actionTitle: "perpsViewPosition".localized
                ) {
                    sheet = nil
                    if viewModel.position != nil { router.navigate(to: PerpsRoute.position(vault: vault, coin: coin)) }
                }
            }
        }
    }

    private func handOff(_ document: PerpsReviewDocument) {
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

/// The first load failed, so there is no price to show: say so and retry every
/// few seconds, instead of an empty screen with disabled buttons.
private struct PerpsMarketUnavailableBanner: View {
    @ObservedObject var connection: PerpsConnection

    var body: some View {
        Group {
            if connection.isOffline {
                PerpsOfflineBanner(message: "perpsMarketUnavailable".localized)
            }
        }
        .task(id: connection.isOffline) {
            while connection.isOffline, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await connection.reconnect()
            }
        }
    }
}
