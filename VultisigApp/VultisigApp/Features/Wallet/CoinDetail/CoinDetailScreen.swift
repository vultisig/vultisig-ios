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
    @State var size: CGFloat?

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
        .background(ModalBackgroundView(width: size ?? 0))
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
        .presentationDetents(isIPadOS ? [.large] : [.medium, .large])
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDragIndicator(.visible)
        .background(Theme.colors.bgSurface1)
        .readSize { size = $0.width }
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
    /// All of it sits *below* the actions deliberately — the sheet opens at
    /// `.medium`, and send/swap/receive must stay above the fold. Dragging up
    /// reveals the chart.
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
            CoinMarketStatsView(stats: stats, ticker: coin.ticker)
            CoinPriceExtremesView(stats: stats)
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
