//
//  TransactionHistoryScreen.swift
//  VultisigApp
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "transaction-history-screen")

struct TransactionHistoryScreen: View {
    @StateObject private var viewModel: TransactionHistoryViewModel

    @Environment(\.openURL) var openURL
    @Environment(\.router) var router

    /// A cancel route parked while the detail sheet dismisses. See `startCancel`.
    @State private var pendingCancelRoute: FunctionCallRoute?

    init(pubKeyECDSA: String, vaultName: String, chainFilter: Chain?) {
        _viewModel = StateObject(wrappedValue: TransactionHistoryViewModel(
            pubKeyECDSA: pubKeyECDSA,
            vaultName: vaultName,
            chainFilter: chainFilter
        ))
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                tabBar
                assetFilterChips
                content
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            bottomGradient
        }
        .screenTitle("transactionHistory".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        .onAppear {
            viewModel.load()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .limitOrdersDidChange)) { _ in
            // `LimitOrder` is a nested `@Model` array on the vault, and
            // in-place mutations of those don't propagate to an
            // `@ObservedObject` here — so without this the tracker's writes
            // (fill progress, expiry countdown, terminal status) would be
            // invisible until the screen was rebuilt.
            //
            // Hopped to the next main-actor turn on purpose. The tracker writes
            // `LimitOrder` FIRST (it's authoritative) and mirrors the coarse
            // status onto the tx-history row second; this notification is
            // posted by that first write and delivered synchronously. Reloading
            // inline would therefore read the row from BEFORE the mirror and
            // pin the card's headline one poll behind its own detail rows.
            // Yielding lets the tracker finish both writes first.
            Task { @MainActor in
                viewModel.reloadAfterLimitOrderChange()
            }
        }
        .crossPlatformSheet(
            item: $viewModel.selectedDetail,
            onDismiss: navigateToPendingCancelIfNeeded
        ) { detail in
            detailSheet(for: detail)
        }
        .crossPlatformSheet(isPresented: $viewModel.showAssetFilter) {
            TransactionHistoryAssetFilterView(
                viewModel: viewModel,
                isPresented: $viewModel.showAssetFilter
            )
        }
        .onChange(of: viewModel.showAssetFilter) { _, isShowing in
            if !isShowing {
                viewModel.filterSearchText = ""
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: .zero) {
            SegmentedControl(
                selection: $viewModel.selectedTab,
                items: TransactionHistoryTab.allCases.map {
                    SegmentedControlItem(value: $0, title: $0.title)
                }
            )
            .fixedSize()

            Spacer()

            CircularAccessoryIconButton(icon: .magnifier) {
                viewModel.showAssetFilter = true
            }
        }
    }

    // MARK: - Asset Filter Chips

    @ViewBuilder
    private var assetFilterChips: some View {
        let assets = viewModel.selectedFilterAssets
        if !assets.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(assets, id: \.ticker) { asset in
                        assetChip(asset)
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.clearAssetFilters()
                    }
                } label: {
                    Text("clearFilters".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.alertInfo)
                }
            }
            .padding(.top, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func assetChip(_ asset: TransactionHistoryCoinAsset) -> some View {
        HStack(spacing: 6) {
            AsyncImageView(
                logo: asset.logo,
                size: CGSize(width: 16, height: 16),
                ticker: asset.ticker,
                tokenChainLogo: asset.chainLogo
            )

            Text("\(asset.ticker) (\(asset.network))")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)

            Image(systemName: "xmark")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .padding(4)
                .background(Circle().fill(Theme.colors.bgPrimary.opacity(0.22)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(6)
        .transition(.opacity.combined(with: .scale))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.removeAssetFilter(asset.ticker)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let grouped = viewModel.groupedTransactions

        ScrollView(showsIndicators: false) {
            if grouped.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.title) { section in
                        CommonListHeaderView(title: section.title, subtitle: section.subtitle)

                        ForEach(section.transactions) { tx in
                            cardView(for: tx)
                                .onTapGesture {
                                    viewModel.selectedDetail = tx
                                }
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var bottomGradient: some View {
        LinearGradient(
            colors: [
                Theme.colors.bgPrimary,
                Theme.colors.bgPrimary.opacity(0)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: 40)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func cardView(for tx: TransactionHistoryData) -> some View {
        TransactionHistoryCardView(transaction: tx, limitOrder: viewModel.limitOrder(for: tx))
    }

    private var emptyState: some View {
        ActionBannerView(
            icon: .calendarDays,
            title: "noTransactionsYet".localized,
            subtitle: "noTransactionsYetSubtitle".localized,
            buttonTitle: "",
            showsActionButton: false,
            action: {}
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Detail Sheet

    private func detailSheet(for detail: TransactionHistoryData) -> some View {
        TransactionHistoryDetailSheet(
            transaction: detail,
            limitOrder: viewModel.limitOrder(for: detail),
            // Whether this DEVICE can send a cancel at all, independent of
            // whether the ORDER is cancellable. Resolved here because only the
            // screen can see the vault; the sheet renders a disabled button with
            // a reason rather than an enabled one whose tap does nothing.
            canSendCancel: cancelSigningCoin != nil,
            onCancelOrder: startCancel
        )
    }

    /// The vault's canonical RUNE coin, which is what signs the cancel deposit.
    ///
    /// `isRune` rather than `chain == .thorChain && isNativeToken`: the latter
    /// admits any THORChain coin flagged native, so duplicated or malformed
    /// persisted coin data could hand the transaction flow a `CoinMeta` that
    /// isn't RUNE at all.
    private var cancelSigningCoin: Coin? {
        guard let vault = try? LimitOrderStorageService.vault(pubKeyECDSA: viewModel.pubKeyECDSA) else {
            return nil
        }
        return vault.coins.first(where: { $0.isRune })
    }

    /// Dismiss the sheet, THEN navigate — in that order, and not concurrently.
    ///
    /// The router pushes onto the navigation stack this screen sits in, which is
    /// behind the presented sheet. Clearing `selectedDetail` only STARTS an
    /// animated dismissal, so pushing in the same turn races it and the
    /// destination can be dropped entirely. The route is parked and replayed
    /// from the sheet's `onDismiss`, once dismissal has actually settled.
    private func startCancel(_ order: LimitOrderDetails) {
        guard let request = viewModel.cancelRequest(for: order),
              let vault = try? LimitOrderStorageService.vault(pubKeyECDSA: viewModel.pubKeyECDSA),
              let runeCoin = vault.coins.first(where: { $0.isRune }) else {
            // Unreachable in practice — the button is only enabled when both the
            // order and `cancelSigningCoin` check out — but a state change under
            // the user must not navigate to a half-built screen.
            logger.error("Cancel tapped but the request could not be assembled")
            return
        }
        pendingCancelRoute = FunctionCallRoute.functionTransaction(
            vault: vault,
            transactionType: .cancelLimitOrder(coin: runeCoin.toCoinMeta(), request: request)
        )
        viewModel.selectedDetail = nil
    }

    private func navigateToPendingCancelIfNeeded() {
        guard let route = pendingCancelRoute else { return }
        pendingCancelRoute = nil
        router.navigate(to: route)
    }
}
