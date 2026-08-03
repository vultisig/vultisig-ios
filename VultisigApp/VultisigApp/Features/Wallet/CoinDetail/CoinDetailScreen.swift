//
//  CoinDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import SwiftUI

struct CoinDetailScreen: View {
    let coin: Coin
    let vault: Vault
    @Binding var isPresented: Bool
    var onCoinAction: (VaultAction) -> Void

    @State var showReceiveSheet: Bool = false
    @State var addressToCopy: Coin?
    @State var showContractCopiedBanner: Bool = false

    /// Where the sheet is resting. Purely presentation state — it never leaves
    /// the view, so it stays here rather than in the view model.
    @State private var detent: PresentationDetent = CoinDetailScreen.initialDetent

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

    /// Resting height of the sheet on iPhone, as a fraction of its full height.
    ///
    /// Measured against a rendered sheet rather than picked as a ratio: 0.50
    /// puts the sheet at ~405pt on an iPhone 16 Pro, the shortest height that
    /// still clears the balance, the whole action row and the top of the price
    /// chart — what the sheet is opened for. A third of the screen, the first
    /// guess, cuts through the action labels and shows no chart at all.
    private static let partialFraction: CGFloat = 0.50

    /// iPad presents this as a large sheet and macOS sizes it with
    /// `applySheetSize`; only iPhone has a partial resting height.
    private static var supportsPartialDetent: Bool {
        !isIPadOS && !isMacOS
    }

    /// `.large` stays in the set alongside the partial height so one drag still
    /// reveals the chart and the market sections.
    private static var detents: Set<PresentationDetent> {
        supportsPartialDetent ? [.fraction(partialFraction), .large] : [.large]
    }

    private static var initialDetent: PresentationDetent {
        supportsPartialDetent ? .fraction(partialFraction) : .large
    }

    /// Whether the sheet is resting below its full height.
    private var isPartial: Bool {
        Self.supportsPartialDetent && detent != .large
    }

    /// Scroll target for the top of the content, used to rewind the scroll
    /// view when the sheet returns to its resting height.
    private static let topAnchor = "coinDetailTop"

    @ViewBuilder
    private var bottomFade: some View {
        if Self.supportsPartialDetent {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Theme.colors.bgSurface1, location: 0.0),
                    Gradient.Stop(color: Theme.colors.bgSurface1.opacity(0.55), location: 0.40),
                    Gradient.Stop(color: Theme.colors.bgSurface1.opacity(0), location: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 64)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .opacity(isPartial ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isPartial)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    var content: some View {
        ScrollViewReader { proxy in
            scrollView
                // Collapsing while scrolled would otherwise strand the user
                // mid-content with scrolling switched off — and the actions,
                // which are what the sheet is opened for, off the top of it.
                .onChange(of: isPartial) { _, isNowPartial in
                    guard isNowPartial else { return }
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
        }
    }

    /// The sheet's scrolling body. Split out of `content` so the
    /// `ScrollViewReader` that rewinds it stays a thin wrapper.
    private var scrollView: some View {
        ScrollView {
            VStack(spacing: 24) {
                CoinDetailHeaderView(coin: coin)
                    .id(Self.topAnchor)
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
        .scrollDisabled(isPartial)
        .overlay(bottomFade)
        .task {
            viewModel.setup()
        }
        .onAppear(perform: onAppear)
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
        .refreshable {
            await refresh()
        }
        .presentationDetents(Self.detents, selection: $detent)
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
    func onAppear() {
        Task {
            await refresh()
        }
    }

    func onRefreshButton() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await BalanceService.shared.updateBalance(for: coin)
        if viewModel.isTron {
            await MainActor.run { viewModel.tronLoader?.load() }
        }
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
