//
//  CoinDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import BigInt
import SwiftUI

struct CoinDetailScreen: View {
    let coin: Coin
    let vault: Vault
    @Binding var isPresented: Bool
    var onCoinAction: (VaultAction) -> Void

    @State var showReceiveSheet: Bool = false
    @State var addressToCopy: Coin?
    @State var showContractCopiedBanner: Bool = false

    @StateObject var viewModel: CoinDetailViewModel

    @Environment(\.openURL) var openURL

    init(
        coin: Coin,
        vault: Vault,
        isPresented: Binding<Bool>,
        onCoinAction: @escaping (VaultAction) -> Void
    ) {
        self.coin = coin
        self.vault = vault
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: .init(coin: coin))
        self.onCoinAction = onCoinAction
    }

    var body: some View {
        container
    }

    var container: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
            .presentationSizingFitted()
            // Tall enough for the chart plus the market sections. The previous
            // 450pt was sized for a header, the actions and two rows; anything
            // below the actions was clipped on the Mac.
            .applySheetSize(700, 760)
#endif
    }

    var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                CoinDetailHeaderView(coin: coin)
                CoinActionsView(
                    actions: viewModel.availableActions,
                    onAction: onAction
                )
                .padding(.bottom, 8)

                if viewModel.isTron {
                    TronResourcesCardView(
                        availableBandwidth: viewModel.tronLoader?.availableBandwidth ?? 0,
                        totalBandwidth: viewModel.tronLoader?.totalBandwidth ?? 0,
                        availableEnergy: viewModel.tronLoader?.availableEnergy ?? 0,
                        totalEnergy: viewModel.tronLoader?.totalEnergy ?? 0,
                        isLoading: viewModel.tronLoader?.isLoading ?? false
                    )
                }

                marketSections
            }
            .padding(.horizontal, 24)
            .padding(.top, isMacOS ? 40 : 0)
            .padding(.bottom, 24)
        }
        .task {
            viewModel.setup()
            await refreshAndRecordIncomingAfterDwell()
        }
        .withAddressCopy(coin: $addressToCopy)
        .overlay(
            NotificationBannerView(
                text: "contractAddressCopied".localized,
                isVisible: $showContractCopiedBanner
            )
            .padding(.bottom, isMacOS ? 24 : 0)
            .showIf(showContractCopiedBanner)
            .zIndex(2)
        )
        .presentationDetents([.large])
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDragIndicator(.visible)
        .background(Theme.colors.bgSurface1)
        .crossPlatformSheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(
                coin: coin,
                isNativeCoin: false,
                onClose: { showReceiveSheet = false },
                onShare: { showReceiveSheet = false },
                onCopy: { coin in
                    showReceiveSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        addressToCopy = coin
                    }
                }
            )
        }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            #if os(macOS)
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented.toggle()
                }
            }
            CustomToolbarItem(placement: .trailing) {
                RefreshToolbarButton(onRefresh: onRefreshButton)
            }
            #endif

            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: .cube, action: onExplorer)
            }
        }
    }

    /// Chart and market sections, in the order they earn their place: the chart
    /// first, then the numbers behind it, then the asset's own details.
    ///
    /// All of it sits *below* the actions deliberately — send/swap/receive are
    /// what the sheet is opened for, so they keep the top of the scroll view and
    /// stay reachable without a scroll. The market data is reference material
    /// and can afford to be scrolled to.
    @ViewBuilder
    var marketSections: some View {
        if viewModel.showsChartSection {
            CoinPriceChartView(
                chart: viewModel.chart,
                range: viewModel.selectedRange,
                isLoading: viewModel.isLoadingChart,
                spotPrice: Decimal(coin.price),
                changeFraction: viewModel.displayedChangeFraction,
                isPositive: viewModel.isChangePositive,
                onSelectRange: viewModel.selectRange
            )
        }

        if let stats = viewModel.stats {
            // Each card decides for itself whether it has rows: a `/markets`
            // record can come back with an id and almost nothing else, and a
            // titled card with no rows in it is worse than no card.
            let marketStats = CoinMarketStatsView(stats: stats, ticker: coin.ticker)
            if marketStats.hasContent {
                marketStats
            }

            let extremes = CoinPriceExtremesView(stats: stats)
            if extremes.hasContent {
                extremes
            }
        }

        CoinTokenInfoView(
            coin: coin,
            price: viewModel.showsChartSection ? nil : Decimal(coin.price).formatToFiatPrice(),
            onCopyContract: onCopyContract,
            onOpenExplorer: onExplorer
        )
    }
}

private extension CoinDetailScreen {
    func onRefreshButton() {
        Task {
            await refresh()
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        let didRefreshBalance = await BalanceService.shared.updateBalance(for: coin)
        if viewModel.isTron {
            await MainActor.run { viewModel.tronLoader?.load() }
        }
        return didRefreshBalance
    }

    func refreshAndRecordIncomingAfterDwell() async {
        // `rawBalance` is the persisted result of the last successful live
        // refresh. Capture it before refreshing so funds that arrived while
        // this screen was closed are recognized on their first live sighting.
        let previouslyObservedRawBalance = coin.rawBalance
        let refreshSucceeded = await refresh()
        let coinPrice = coin.price
        let candidateEventID = AppReviewIncomingBalancePolicy.eventID(
            coinID: coin.id,
            previousRawBalance: previouslyObservedRawBalance,
            currentRawBalance: coin.rawBalance,
            decimals: coin.decimals,
            fiatRate: coinPrice.isFinite && coinPrice > 0 ? Decimal(coinPrice) : nil,
            isNativeToken: coin.isNativeToken,
            minimumRawAmount: BigInt(coin.coinType.getFixedDustThreshold()),
            isLikelySpam: CoinService.isLikelySpam(coin.toCoinMeta()),
            refreshSucceeded: refreshSucceeded
        )

        // The live confirmed balance is already persisted by `refresh()`. Only
        // the review event waits: SwiftUI cancels this task if the sheet
        // disappears before the user has dwelled on the visible balance.
        guard let eventID = await AppReviewIncomingBalancePolicy.eventIDAfterDwell(candidateEventID) else {
            return
        }

        AppReviewService.shared.record(
            .confirmedIncomingTransaction(id: eventID)
        )
        AppReviewService.shared.requestPromptEvaluation()
    }

    func onExplorer() {
        if
            let url = Endpoint.getExplorerByCoinURL(coin: coin),
            let linkURL = URL(string: url) {
            openURL(linkURL)
        }
    }

    func onCopyContract(_ contract: String) {
        ClipboardManager.copyToClipboard(contract)
        showContractCopiedBanner = true
    }

    func onAction(_ action: CoinAction) {
        var vaultAction: VaultAction?
        switch action {
        case .receive:
            showReceiveSheet = true
        case .send:
            vaultAction = .send(coin: coin, hasPreselectedCoin: true)
        case .swap:
            vaultAction = .swap(fromCoin: coin)
        case .deposit, .bridge, .memo:
            vaultAction = .function(coin: coin)
        case .buy:
            vaultAction = .buy(
                address: coin.address,
                blockChainCode: coin.chain.banxaBlockchainCode,
                coinType: coin.ticker
            )
        case .sell:
            break
        }

        guard let vaultAction else { return }
        onCoinAction(vaultAction)
    }
}

#Preview {
    CoinDetailScreen(
        coin: .example,
        vault: .example,
        isPresented: .constant(true),
        onCoinAction: { _ in}
    )
}
