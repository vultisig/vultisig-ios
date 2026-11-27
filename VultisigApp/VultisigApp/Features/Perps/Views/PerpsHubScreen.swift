//
//  PerpsHubScreen.swift
//  VultisigApp
//
//  Perps hub. First visit: one intro card and three
//  markets. Funded: the equity, what is available, positions, markets.
//  Money actions sit behind the equity (add funds, withdraw, enable trading).
//

import SwiftUI
import VultisigUIResources

struct PerpsHubScreen: View {
    let vault: Vault

    private enum SheetKind: Identifiable, Equatable {
        case funds, learnMore, account, addingFunds(Decimal), withdrawing(PerpsWithdrawQuote), withdrawn(PerpsWithdrawQuote)
        case withdrawSlow(PerpsPendingWithdrawal)
        var id: String {
            switch self {
            case .withdrawSlow: return "withdrawSlow"
            case .funds: return "funds"
            case .withdrawing: return "withdrawing"
            case .withdrawn: return "withdrawn"
            case .learnMore: return "learnMore"
            case .account: return "account"
            case .addingFunds: return "addingFunds"
            }
        }
    }

    @StateObject private var viewModel = PerpsHubViewModel()
    @Environment(\.router) private var router
    @Environment(\.openURL) private var openURL
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter
    @State private var sheet: SheetKind?
    @State private var pendingReview: PerpsReviewDocument?
    @State private var pendingSheet: SheetKind?
    /// Debug story: a review this screen opened is on screen.
    @State private var didPresentReview = false

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: PerpsLayout.section) {
                    if viewModel.isFirstVisit {
                        introCard
                    } else if viewModel.account?.positions.isEmpty ?? true {
                        noTradesHeader
                    } else {
                        fundedHeader
                        positions
                    }
                    explore
                    if PerpsConfig.showsDebugDetails { debugLinks }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { await viewModel.load(vault: vault) }
        }
        .screenTitle("perpsTitle".localized)
        .perpsScreenMargins()
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: .clockRotateClockwise) { router.navigate(to: PerpsRoute.activity(vault: vault)) }
                    .accessibilityIdentifier("perpsActivityButton")
            }
        }
        .task {
            await viewModel.load(vault: vault)
            presentDemoState()
        }
        .onAppear(perform: presentStoryWithdrawing)
        // Debug story only: closing the deposit review stands in for signing it.
        .onChange(of: reviewPresenter.presented == nil) { _, isClosed in
            guard isClosed, didPresentReview else { return }
            didPresentReview = false
            #if DEBUG
            guard PerpsDemoStory.isOn, PerpsDemoStory.stage == .empty else { return }
            PerpsDemoStory.stage = .funded
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                sheet = .addingFunds(PerpsDemoRepository.deposited)
            }
            #endif
        }
        .crossPlatformSheet(item: $sheet, onDismiss: sheetDidDismiss) { kind in
            sheetContent(kind)
        }
    }

    /// Debug story: back from the withdraw screen after its review, the hub
    /// shows the account without the $100 and the Withdrawing sheet over it.
    private func presentStoryWithdrawing() {
        #if DEBUG
        guard PerpsDemoStory.isOn, PerpsDemoStory.takeWithdrawingPending() else { return }
        Task { @MainActor in
            await viewModel.load(vault: vault)
            try? await Task.sleep(for: .milliseconds(400))
            sheet = .withdrawing(PerpsWithdrawQuote(amount: PerpsDemoRepository.demoWithdrawal,
                                                    withdrawable: (viewModel.account?.availableToWithdraw ?? 0) + PerpsDemoRepository.demoWithdrawal,
                                                    fee: PerpsConfig.withdrawFee,
                                                    activationFee: PerpsConfig.withdrawActivationFee(hasWithdrawnBefore: false)))
        }
        #endif
    }

    // MARK: First visit

    /// The Vultisig mark, one line, one action, and a text link.
    private var introCard: some View {
        VStack(spacing: 10) {
            VultisigImage("vultisig-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
            Text("perpsIntroTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("perpsIntroBody".localized)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "perpsAddFunds".localized) { sheet = .funds }
                .accessibilityIdentifier("perpsAddFunds")
                .padding(.top, 10)
            Button { sheet = .learnMore } label: {
                Text("perpsLearnMore".localized)
                    .font(Theme.fonts.subtitle)
                    .foregroundStyle(Theme.colors.primaryAccent4)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perpsLearnMore")
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: Funded

    private var fundedHeader: some View {
        Button { sheet = .account } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(PerpsFormat.usd(viewModel.account?.equity ?? 0))
                    .font(Theme.fonts.priceLargeTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                HStack(spacing: 4) {
                    Text(String(format: "perpsAvailableAmount".localized, PerpsFormat.usd(viewModel.account?.availableToTrade ?? 0)))
                        .font(Theme.fonts.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.colors.textTertiary)
                    Icon(.chevronRightSmall, color: Theme.colors.textSecondary, size: 16)
                }
            }
            // The whole balance block is the tap target for the trading account.
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("perpsEquity")
    }

    /// funded, no trades: what can be traded, "No open positions", and a
    /// round + to add more. Explore below is where a first trade starts.
    private var noTradesHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { sheet = .account } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PerpsFormat.usd(viewModel.account?.availableToTrade ?? 0))
                        .font(Theme.fonts.priceLargeTitle)
                        .monospacedDigit()
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("perpsAvailableToTrade".localized + " · " + "perpsNoOpenPositions".localized)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perpsEquity")
            Button { sheet = .funds } label: {
                Icon(.plus, color: Theme.colors.textPrimary, size: 18)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.colors.bgSurface1))
                    .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("perpsAddFunds".localized)
            .accessibilityIdentifier("perpsHubAddFunds")
        }
    }

    @ViewBuilder
    private var positions: some View {
        let positions = viewModel.account?.positions ?? []
        VStack(spacing: 12) {
            PerpsSectionHeader(title: "perpsPositions".localized)
            if positions.isEmpty {
                Text("perpsNoPositionsYet".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                PerpsCard {
                    ForEach(Array(positions.enumerated()), id: \.element.coin) { index, position in
                        if index > 0 { Separator(color: Theme.colors.borderLight, opacity: 1) }
                        Button {
                            router.navigate(to: PerpsRoute.position(vault: vault, coin: position.coin))
                        } label: {
                            PerpsPositionListRow(position: position)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("perpsPosition-\(position.coin)")
                    }
                }
            }
        }
    }

    // MARK: Markets

    private var explore: some View {
        VStack(spacing: 12) {
            PerpsSectionHeader(
                title: "perpsExplore".localized,
                action: ("perpsSeeAll".localized, { router.navigate(to: PerpsRoute.search(vault: vault)) })
            )
            PerpsCard {
                ForEach(Array(viewModel.exploreMarkets.enumerated()), id: \.element.id) { index, market in
                    if index > 0 { Separator(color: Theme.colors.borderLight, opacity: 1) }
                    Button {
                        router.navigate(to: PerpsRoute.market(vault: vault, coin: market.coin))
                    } label: {
                        PerpsMarketListRow(market: market)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("perpsMarket-\(market.coin)")
                }
            }
            if let error = viewModel.errorMessage {
                Text(error).font(Theme.fonts.caption12).foregroundStyle(Theme.colors.alertError)
            }
        }
    }

    private var debugLinks: some View {
        Button { router.navigate(to: PerpsRoute.dryRunLog) } label: {
            Text("Dry-run log (\(HyperliquidExchangeDryRunClient.shared.log.count))")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ kind: SheetKind) -> some View {
        switch kind {
        case .withdrawing(let quote):
            // A sheet over the hub, like Adding funds; closing it does not stop the transfer.
            PerpsResultSheet(
                mark: .pending,
                title: String(format: "perpsWithdrawingAmount".localized, PerpsFormat.amount(quote.amount)),
                message: "perpsWithdrawingMessage".localized,
                statusRows: [
                    PerpsReviewRow(label: "perpsLeftTradingAccount".localized, value: "perpsStatusDone".localized, tone: .positive),
                    PerpsReviewRow(label: "perpsArrivingInVault".localized, value: "perpsStatusInProgress".localized, tone: .muted)
                ],
                actionTitle: "perpsHide".localized,
                actionType: .secondary
            ) { sheet = nil }
        case .withdrawSlow(let pending):
            // calm and factual; the transfer keeps going when this closes.
            PerpsResultSheet(
                mark: .waiting,
                title: "perpsTakingLonger".localized,
                message: String(format: "perpsTakingLongerBody".localized, PerpsFormat.amount(pending.amount), PerpsFormat.usd(pending.receive)),
                statusRows: [
                    PerpsReviewRow(label: "perpsLeftTradingAccount".localized, value: "perpsStatusDone".localized, tone: .positive),
                    PerpsReviewRow(label: "perpsArrivingInVault".localized,
                                   value: String(format: "perpsStartedMinAgo".localized, pending.minutesAgo()), tone: .muted)
                ],
                actionTitle: "perpsHide".localized,
                actionType: .secondary,
                helpLine: ("perpsNotThereInAnHour".localized, "perpsGetHelp".localized, {
                    // The app's existing support channel.
                    openURL(StaticURL.DiscordVultisigURL)
                })
            ) { sheet = nil }
        case .withdrawn(let quote):
            PerpsResultSheet(
                mark: .success,
                title: String(format: "perpsWithdrawnTitle".localized, PerpsFormat.usd(quote.receive)),
                message: "perpsUsdcOnArbitrum".localized,
                actionTitle: "perpsDone".localized
            ) { sheet = nil }
        case .funds:
            PerpsFundsSheet(account: viewModel.account, vault: PerpsVaultContext(vault: vault),
                            prefill: demoDepositPrefill) { document in
                pendingReview = document
                sheet = nil
            }
        case .learnMore:
            PerpsLearnMoreSheet { sheet = nil }
        case .addingFunds(let amount):
            PerpsResultSheet(
                mark: .pending,
                title: String(format: "perpsAddingAmount".localized, PerpsFormat.usd(amount)),
                message: "perpsAddingMessage".localized,
                statusRows: [
                    PerpsReviewRow(label: "perpsSentFromVault".localized, value: "perpsStatusDone".localized, tone: .positive),
                    PerpsReviewRow(label: "perpsAddingToTradingAccount".localized, value: "perpsStatusInProgress".localized, tone: .muted)
                ],
                // Hiding the sheet does not stop the transfer.
                actionTitle: "perpsHide".localized,
                actionType: .secondary
            ) {
                sheet = nil
                #if DEBUG
                // Debug story: the funds have arrived by the time the sheet is hidden.
                if PerpsDemoStory.isOn { Task { await viewModel.load(vault: vault) } }
                #endif
            }
        case .account:
            PerpsAccountSheet(
                summary: viewModel.account.map(PerpsAccountSummary.make) ?? PerpsAccountSummary(available: 0, inPositions: 0),
                onAddFunds: { switchSheet(to: .funds) },
                onWithdraw: {
                    sheet = nil
                    router.navigate(to: PerpsRoute.withdraw(vault: vault))
                }
            )
        }
    }

    /// Debug story: the deposit that lands as exactly $250 after its fees.
    private var demoDepositPrefill: Decimal? {
        #if DEBUG
        PerpsDemoStory.isOn ? PerpsDemoStory.depositPrefill : nil
        #else
        nil
        #endif
    }

    /// Debug only: states a dry run never reaches on its own.
    private func presentDemoState() {
        #if DEBUG
        let state = PerpsDemoState.current
        if state.contains(.addingFunds) { sheet = .addingFunds(PerpsDemoRepository.deposited) }
        if state.contains(.withdraw) { router.navigate(to: PerpsRoute.withdraw(vault: vault)) }
        if let account = viewModel.account { presentDemoAccountState(state, account: account) }
        #endif
        presentSlowWithdrawal()
    }

    #if DEBUG
    private func presentDemoAccountState(_ state: Set<PerpsDemoState>, account: PerpsAccountSnapshot) {
        // The account already reflects the withdrawal; quote it as it was before.
        let before = PerpsWithdrawQuote(amount: PerpsDemoRepository.demoWithdrawal,
                                        withdrawable: account.availableToWithdraw + PerpsDemoRepository.demoWithdrawal,
                                        fee: PerpsConfig.withdrawFee,
                                        activationFee: PerpsConfig.withdrawActivationFee(hasWithdrawnBefore: false))
        if state.contains(.withdrawing) { sheet = .withdrawing(before) }
        if state.contains(.withdrawn) { sheet = .withdrawn(before) }
        if state.contains(.account) { sheet = .account }
        if PerpsConfig.usesDemoAccount {
            if state.contains(.withdrawSlow) {
                PerpsPendingWithdrawalStore.save(PerpsPendingWithdrawal(amount: before.amount, receive: before.receive,
                                                                        startedAt: Date().addingTimeInterval(-14 * 60),
                                                                        account: account.address.lowercased(), isDemo: true))
            } else {
                PerpsPendingWithdrawalStore.clear()
            }
        }
    }
    #endif

    /// A withdrawal that left the trading account more than ten minutes ago
    /// and has not arrived: kept across launches, shown once per visit.
    private func presentSlowWithdrawal() {
        guard sheet == nil, let account = viewModel.account?.address,
              let pending = PerpsPendingWithdrawalStore.load(account: account, includeDemo: includesDemoWithdrawals),
              pending.isSlow() else { return }
        sheet = .withdrawSlow(pending)
    }

    private var includesDemoWithdrawals: Bool {
        #if DEBUG
        PerpsConfig.usesDemoAccount
        #else
        false
        #endif
    }

    private func switchSheet(to next: SheetKind) {
        pendingSheet = next
        sheet = nil
    }

    private func sheetDidDismiss() {
        if let next = pendingSheet {
            pendingSheet = nil
            sheet = next
        } else if let document = pendingReview {
            pendingReview = nil
            didPresentReview = true
            reviewPresenter.present(.perps(request: PerpsReviewRequest(document: document), vaultPubKeyECDSA: vault.pubKeyECDSA))
        }
    }
}

// MARK: - Shared bits

struct PerpsChangeChip: View {
    let text: String
    let isPositive: Bool

    var body: some View {
        let tint = isPositive ? Theme.colors.alertSuccess : Theme.colors.alertError
        Text(text)
            .font(Theme.fonts.caption12)
            .foregroundStyle(tint)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct PerpsCoinBadge: View {
    let coin: String
    var size: CGFloat = 32

    private static let logoOverrides = ["SOL": "solana", "HYPE": "hyperliquid"]

    var body: some View {
        AsyncImageView(
            logo: Self.logoOverrides[coin] ?? coin.lowercased(),
            size: CGSize(width: size, height: size),
            ticker: coin,
            tokenChainLogo: nil
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Logo, symbol with a "Long 4×" chip, size; P&L and return on the right.
struct PerpsPositionListRow: View {
    let position: HLPosition

    var body: some View {
        let pnl = position.unrealizedPnl.value
        let tint = pnl >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError
        HStack(spacing: 12) {
            PerpsCoinBadge(coin: position.coin, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(position.coin)
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                    PerpsChangeChip(text: (position.isLong ? "perpsLongTitle".localized : "perpsShortTitle".localized) + " \(position.leverage.value)×",
                                    isPositive: position.isLong)
                }
                Text("\(HLWireFormat.decimalString(abs(position.szi.value))) \(position.coin)")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(PerpsFormat.usd(pnl, signed: true))
                    .font(Theme.fonts.priceBodyS)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(PerpsFormat.percent(position.returnOnEquity.value * 100, digits: 1))
                    .font(Theme.fonts.priceCaption)
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
