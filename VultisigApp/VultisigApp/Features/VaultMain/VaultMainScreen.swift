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
    @Binding var showVaultSelector: Bool
    @Binding var addressToCopy: Coin?
    @Binding var showUpgradeVaultSheet: Bool
    
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @State private var scrollOffset: CGFloat = 0
    @State var showBalanceInHeader: Bool = false
    @State var showChainSelection: Bool = false
    @State var showSearchHeader: Bool = false
    @State var showReceiveList: Bool = false
    @State var focusSearch: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    @State var frameHeight: CGFloat = 0
    
    private let scrollReferenceId = "vaultMainScreenBottomContentId"
    
    private let contentInset: CGFloat = 78
    
    var shouldRefresh: Bool {
        !showChainSelection
    }
    
    var body: some View {
        VStack {
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    OffsetObservingScrollView(
                        showsIndicators: false,
                        contentInset: contentInset,
                        ns: .scrollView,
                        scrollOffset: $scrollOffset
                    ) {
                        LazyVStack(spacing: 20) {
                            topContentSection
                            Separator(color: Theme.colors.borderLight, opacity: 1)
                            bottomContentSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .onLoad {
                        scrollProxy = proxy
                    }
                }
                header
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(VaultMainScreenBackground())
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
            .sheet(isPresented: $showVaultSelector) {
                VaultManagementSheet {
                    showVaultSelector.toggle()
                    routeToPresent = .createVault
                } onSelectVault: { vault in
                    showVaultSelector.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        homeViewModel.setSelectedVault(vault)
                    }
                }
            }
            .sheet(isPresented: $showChainSelection) {
                VaultSelectChainScreen(
                    vault: homeViewModel.selectedVault ?? .example,
                    isPresented: $showChainSelection
                )
            }
            .sheet(isPresented: $showBackupNow) {
                VaultBackupNowScreen(tssType: .Keygen, backupType: .single(vault: vault))
            }
            .platformSheet(isPresented: $showReceiveList) {
                ReceiveChainSelectionScreen(
                    vault: vault,
                    isPresented: $showReceiveList,
                    viewModel: viewModel
                )
            }
            .onAppear(perform: refresh)
            .refreshable { refresh() }
            .onChange(of: homeViewModel.selectedVault?.coins) {
                refresh()
            }
            .onChange(of: settingsViewModel.selectedCurrency) {
                refresh()
            }
            .id(vault.id)
        }
    }
    
    var header: some View {
        VaultMainHeaderView(
            vault: vault,
            showBalance: $showBalanceInHeader,
            vaultSelectorAction: onVaultSelector,
            settingsAction: { routeToPresent = .settings }
        )
    }
    
    var topContentSection: some View {
        LazyVStack(spacing: 32) {
            VaultMainBalanceView(vault: vault)
            CoinActionsView(
                actions: viewModel.availableActions,
                onAction: onAction
            )
            upgradeVaultBanner
        }
    }
    
    @State var showUpgradeBanner = true
    @ViewBuilder
    var upgradeVaultBanner: some View {
        VaultBannerView(
            title: "signFasterThanEverBefore".localized,
            subtitle: "upgradeYourVaultNow".localized,
            buttonTitle: "upgradeNow".localized,
            bgImage: "referral-banner-2",
            action: { showUpgradeVaultSheet = true },
            onClose: {
                withAnimation {
                    showUpgradeBanner = false
                }
            }
        )
        .transition(.verticalGrowAndFade)
        .showIf(vault.libType == .GG20 && showUpgradeBanner)
    }
    
    @State var showBackupBanner = true
    @State var showBackupNow = false
    @ViewBuilder
    var backupBanner: some View {
        VaultBannerView(
            title: "backupYourVaultNow".localized,
            subtitle: "",
            buttonTitle: "backupNow".localized,
            bgImage: "referral-banner-2",
            action: { showBackupNow = true },
            onClose: {
                withAnimation {
                    showBackupBanner = false
                }
            }
        )
        .transition(.verticalGrowAndFade)
        .showIf(!vault.isBackedUp && showBackupBanner)
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
                onAction: { routeToPresent = .chainDetail($0) },
                onCustomizeChains: onCustomizeChains
            )
            .background(
                // Reference to scroll when search gets presented
                VStack {}
                    .frame(height: 300)
                    .id(scrollReferenceId)
            )
        }
    }
    
    var defaultBottomSectionHeader: some View {
        HStack(spacing: 8) {
            SegmentedControl(
                selection: $viewModel.selectedTab,
                items: viewModel.tabs
            )
            Spacer()
            CircularAccessoryIconButton(icon: "magnifying-glass") {
                toggleSearch()
            }
            CircularAccessoryIconButton(icon: "crypto-wallet-pen", type: .secondary) {
                showChainSelection.toggle()
            }
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
    
    func onVaultSelector() {
        showVaultSelector.toggle()
    }
    
    func onCopy(_ group: GroupedChain) {
        addressToCopy = group.nativeCoin
    }
    
    func refresh() {
        viewModel.updateBalance(vault: vault)
        viewModel.getGroupAsync(tokenSelectionViewModel)
        
        tokenSelectionViewModel.setData(for: vault)
        settingsDefaultChainViewModel.setData(tokenSelectionViewModel.groupedAssets)
        viewModel.categorizeCoins(vault: vault)
    }
    
    func onScrollOffsetChange(_ offset: CGFloat) {
        showBalanceInHeader = offset < contentInset
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
            // TODO: - To add
            break
        case .receive:
            showReceiveList = true
            return
        }
        
        guard let vaultAction else { return }
        routeToPresent = .mainAction(vaultAction)
    }
}

#Preview {
    VaultMainScreen(
        vault: .example,
        routeToPresent: .constant(nil),
        showVaultSelector: .constant(false),
        addressToCopy: .constant(nil),
        showUpgradeVaultSheet: .constant(false)
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
