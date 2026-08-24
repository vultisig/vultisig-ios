//
//  DefiMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/10/2025.
//

import SwiftData
import SwiftUI

struct DefiMainScreen: View {
    @ObservedObject var vault: Vault
    /// Shared with the top bar and written from this screen's scroll offset.
    /// Held as a plain `let`, deliberately un-observed: this screen must not be
    /// invalidated by a scroll, only the leaf that renders the balance is.
    let collapse: HomeHeaderCollapse

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router

    @State var scrollProxy: ScrollViewProxy?
    @State var showSearchHeader: Bool = false
    @State var focusSearch: Bool = false
    @State var showChainSelection: Bool = false
    @State private var clearSearchTask: Task<Void, Never>?
    @State private var refreshTask: Task<Void, Never>?

    private let searchAnchorId = "defiMainSearchHeaderAnchor"
    private let sectionHeaderHeight: CGFloat = 42
    private let contentInset: CGFloat = 78
    private let horizontalPadding: CGFloat = 16

    @StateObject var viewModel = DefiMainViewModel()

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                VaultMainScreenScrollView(
                    showsIndicators: false,
                    topInset: contentInset,
                    bottomInset: 0,
                    onOffsetChange: onScrollOffsetChange
                ) {
                    LazyVStack(spacing: 20) {
                        DefiMainBalanceView(vault: vault)
                            .headerCollapseFade(collapse, tab: .defi)
                        Separator(color: Theme.colors.borderLight, opacity: 1)
                        bottomContentSection
                    }
                    .padding(.bottom, 32)
                    .padding(.horizontal, horizontalPadding)
                }
                .onLoad {
                    scrollProxy = proxy
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MainBackgroundWithNotification())
            .onChange(of: showSearchHeader) { _, showSearchHeader in
                guard showSearchHeader else { return }
                focusSearch = true
                withAnimation {
                    scrollProxy?.scrollTo(searchAnchorId, anchor: .top)
                }
            }
            .crossPlatformSheet(isPresented: $showChainSelection) {
                DefiSelectChainScreen(
                    vault: vault,
                    isPresented: $showChainSelection
                ) { refresh() }
            }
            .refreshable { refresh() }
            .onChange(of: settingsViewModel.selectedCurrency) {
                refresh()
            }
        }
        .throttledOnAppear(interval: 15.0, action: refresh)
        .onChange(of: vault) { _, _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .defiPositionsDidChange)) { _ in
            // Position-only balances (Kamino, LPs, bonds and persisted stake
            // rows) do not necessarily mutate a wallet coin. Rebuild the order
            // from the displayed totals whenever their shared store changes.
            viewModel.groupChains(vault: vault)
        }
        .onDisappear {
            clearSearchTask?.cancel()
            refreshTask?.cancel()
        }
    }

    var bottomContentSection: some View {
        LazyVStack(spacing: 0) {
            Group {
                if showSearchHeader {
                    searchBottomSectionHeader
                } else {
                    defaultBottomSectionHeader
                }
            }
            .transition(.opacity)
            .frame(height: sectionHeaderHeight)
            .background(searchScrollAnchor)
            .padding(.bottom, 16)

            DefiChainListView(
                vault: vault,
                viewModel: viewModel,
                onCustomizeChains: onCustomizeChains
            )
        }
        .id(vault.id)
    }

    /// Where the section header is parked when search opens.
    ///
    /// A background is centred on its host and does not affect layout, so a box
    /// `2 * contentInset` taller than the header has its top edge exactly
    /// `contentInset` above the header's. Scrolling *that* edge to the top of
    /// the viewport leaves the header one floating-home-header height down —
    /// the same clearance `VaultMainScreenScrollView`'s `topInset` gives the
    /// rest of the content — so the field lands below that header rather than
    /// behind it, with the results underneath it and above the keyboard.
    var searchScrollAnchor: some View {
        Color.clear
            .frame(height: sectionHeaderHeight + 2 * contentInset)
            .id(searchAnchorId)
            .allowsHitTesting(false)
    }

    var defaultBottomSectionHeader: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                Text("portfolio".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Rectangle()
                    .fill(Theme.colors.primaryAccent4)
                    .frame(height: 2)
            }
            .fixedSize()
            Spacer()
            CircularAccessoryIconButton(icon: .magnifier) {
                toggleSearch()
            }
            .accessibilityIdentifier(AccessibilityID.DefiMain.searchButton)
            CircularAccessoryIconButton(icon: .housePen, type: .secondary) {
                showChainSelection.toggle()
            }
        }
    }

    var searchBottomSectionHeader: some View {
        HStack(spacing: 12) {
            SearchTextField(
                value: $viewModel.searchText,
                isFocused: $focusSearch,
                accessibilityIdentifier: AccessibilityID.DefiMain.searchField
            )
            Button(action: clearSearch) {
                Text("cancel".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityIdentifier(AccessibilityID.DefiMain.searchCancelButton)
        }
    }

    func toggleSearch() {
        if showSearchHeader {
            focusSearch.toggle()
        }
        withAnimation(.interpolatingSpring) {
            showSearchHeader.toggle()
        }
    }

    func refresh() {
        // Paint immediately from persisted balances, then kick a fire-and-forget
        // balance refresh so staked positions (e.g. TRON frozen TRX) land even
        // when the user opens DeFi without visiting the Wallet tab first.
        viewModel.groupChains(vault: vault)
        refreshTask?.cancel()
        refreshTask = Task { await viewModel.refreshBalances(vault: vault) }
    }

    func clearSearch() {
        toggleSearch()
        viewModel.searchText = ""
    }

    func onCustomizeChains() {
        showChainSelection = true
        // Clear search after sheet gets presented
        clearSearchTask?.cancel()
        clearSearchTask = delayedTask(after: .seconds(1)) {
            clearSearch()
        }
    }

    func onScrollOffsetChange(_ offset: CGFloat) {
        collapse.update(tab: .defi, offset: offset, restingOffset: contentInset)
    }
}

#Preview {
    DefiMainScreen(
        vault: .example,
        collapse: HomeHeaderCollapse()
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
