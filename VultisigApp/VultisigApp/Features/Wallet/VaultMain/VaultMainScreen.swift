//
//  VaultMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftData
import SwiftUI

struct VaultMainScreen: View {
    @ObservedObject var vault: Vault
    @Binding var routeToPresent: VaultMainRoute?
    @Binding var addressToCopy: Coin?
    @Binding var showUpgradeVaultSheet: Bool
    @Binding var showBackupNow: Bool
    @Binding var showBalanceInHeader: Bool
    @Binding var shouldRefresh: Bool
    var onCamera: () -> Void
    
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.openURL) var openURL
    
    @State private var scrollOffset: CGFloat = 0
    @State var showChainSelection: Bool = false
    @State var showSearchHeader: Bool = false
    @State var showReceiveList: Bool = false
    @State var focusSearch: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    @State var frameHeight: CGFloat = 0
    
    // Capture geometry width to avoid circular layout dependency during sheet presentation
    @State private var capturedGeometryWidth: CGFloat = 400
    
    private let scrollReferenceId = "vaultMainScreenBottomContentId"
    private let contentInset: CGFloat = 78
    private let horizontalPadding: CGFloat = 16
    
    var body: some View {
        GeometryReader { geo in
            VStack {
                ScrollViewReader { proxy in
                    VaultMainScreenScrollView(
                        showsIndicators: false,
                        contentInset: contentInset,
                        scrollOffset: $scrollOffset
                    ) {
                        LazyVStack(spacing: 20) {
                            topContentSection(width: capturedGeometryWidth)
                            Group {
                                Separator(color: Theme.colors.borderLight, opacity: 1)
                                bottomContentSection
                            }
                            .padding(.horizontal, horizontalPadding)
                        }
                        .padding(.bottom, 32)
                    }
                    .onLoad {
                        scrollProxy = proxy
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(VaultMainScreenBackground())
                .onAppear {
                    // Capture geometry width to avoid circular layout dependency
                    capturedGeometryWidth = geo.size.width
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    // Update captured width when geometry changes (but not during sheet presentation)
                    if !showChainSelection && !showReceiveList {
                        capturedGeometryWidth = newWidth
                    }
                }
                .onChange(of: scrollOffset) { _, newValue in
                    onScrollOffsetChange(newValue)
                }
                .onChange(of: showSearchHeader) { _, showSearchHeader in
                    if showSearchHeader {
                        focusSearch = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            withAnimation {
                                scrollProxy?.scrollTo(scrollReferenceId, anchor: .center)
                            }
                        }
                    }
                }
                .crossPlatformSheet(isPresented: $showChainSelection) {
                    VaultSelectChainScreen(
                        vault: vault,
                        isPresented: $showChainSelection
                    ) { refresh() }
                }
                .crossPlatformSheet(isPresented: $showReceiveList) {
                    ReceiveChainSelectionScreen(
                        vault: vault,
                        isPresented: $showReceiveList,
                        viewModel: viewModel,
                        addressToCopy: $addressToCopy
                    )
                }
                .throttledOnAppear(interval: 15.0, action: refresh)
                .refreshable { refresh() }
                .onChange(of: settingsViewModel.selectedCurrency) {
                    refresh()
                }
            }
        }
        .onLoad {
            refresh()
        }
        .onChange(of: vault) { _, _ in
            refresh()
        }
        .onChange(of: shouldRefresh) { _, newValue in
            guard newValue else { return }
            shouldRefresh = false
            refresh()
        }
        .onChange(of: vault.coins) { oldValue, newValue in
            if oldValue.count != newValue.count {
                refresh()
            }
        }
    }
    
    func topContentSection(width: CGFloat) -> some View {
        LazyVStack(spacing: 0) {
            Group {
                VaultMainBalanceView(
                    vault: vault,
                    balanceToShow: homeViewModel.balanceText(for: vault),
                    style: .wallet
                )
                    .padding(.bottom, 32)
                CoinActionsView(
                    actions: viewModel.availableActions,
                    onAction: onAction
                )
            }
            .padding(.horizontal, horizontalPadding)
            
            BannersCarousel(
                banners: $viewModel.vaultBanners,
                availableWidth: width,
                paddingTop: 32,
                onBanner: onBannerPressed,
                onClose: onBannerClosed
            )
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
            .frame(height: 42)
            .padding(.bottom, 16)
            
            VaultMainChainListView(
                vault: vault,
                onCopy: onCopy,
                onCustomizeChains: onCustomizeChains
            )
            .background(
                // Reference to scroll when search gets presented
                VStack {}
                    .frame(height: 300)
                    .id(scrollReferenceId)
            )
        }
        .id(vault.id)
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
            CircularAccessoryIconButton(icon: "magnifying-glass") {
                toggleSearch()
            }
            CircularAccessoryIconButton(icon: "crypto-wallet-pen", type: .secondary) {
                showChainSelection.toggle()
            }
            .showIf(viewModel.canShowChainSelection(vault: vault))
        }
    }
    
    var searchBottomSectionHeader: some View {
        HStack(spacing: 12) {
            SearchTextField(value: $viewModel.searchText, isFocused: $focusSearch)
            Button(action: clearSearch) {
                Text("cancel".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
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
    
    func onCopy(_ group: GroupedChain) {
        addressToCopy = group.nativeCoin
    }
    
    func refresh() {
        tokenSelectionViewModel.setData(for: vault)
        viewModel.setupBanners(for: vault)
        viewModel.getGroupAsync(tokenSelectionViewModel)
        
        viewModel.groupChains(vault: vault)
        viewModel.updateBalance(vault: vault)
    }
    
    func onScrollOffsetChange(_ offset: CGFloat) {
        let showBalanceInHeader: Bool = offset < contentInset
        guard showBalanceInHeader != self.showBalanceInHeader else { return }
        self.showBalanceInHeader = showBalanceInHeader
    }
    
    func clearSearch() {
        toggleSearch()
        viewModel.searchText = ""
    }
    
    func onCustomizeChains() {
        showChainSelection = true
        // Clear search after sheet gets presented
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            clearSearch()
        }
    }
    
    func onAction(_ action: CoinAction) {
        var vaultAction: VaultAction?
        
        switch action {
        case .send:
            vaultAction = .send(coin: viewModel.selectedGroup?.nativeCoin, hasPreselectedCoin: false)
        case .swap:
            guard let fromCoin = viewModel.selectedGroup?.nativeCoin else { return }
            vaultAction = .swap(fromCoin: fromCoin)
        case .deposit, .bridge, .memo:
            vaultAction = .function(coin: viewModel.selectedGroup?.nativeCoin)
        case .buy:
            vaultAction = .buy(
                address: viewModel.selectedGroup?.address ?? "",
                blockChainCode: viewModel.selectedGroup?.chain.banxaBlockchainCode ?? "",
                coinType: viewModel.selectedGroup?.nativeCoin.ticker ?? ""
            )
        case .sell:
            break
        case .receive:
            showReceiveList = true
            return
        }
        
        guard let vaultAction else { return }
        routeToPresent = .mainAction(vaultAction)
    }
    
    func onBannerPressed(_ banner: VaultBannerType) {
        switch banner {
        case .upgradeVault:
            showUpgradeVaultSheet = true
        case .backupVault:
            showBackupNow = true
        case .followVultisig:
            openURL(StaticURL.XVultisigURL)
        }
    }
    
    func onBannerClosed(_ banner: VaultBannerType) {
        viewModel.removeBanner(for: vault, banner: banner)
    }
}

#Preview {
    VaultMainScreen(
        vault: .example,
        routeToPresent: .constant(nil),
        addressToCopy: .constant(nil),
        showUpgradeVaultSheet: .constant(false),
        showBackupNow: .constant(false),
        showBalanceInHeader: .constant(false),
        shouldRefresh: .constant(false),
        onCamera: {}
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
