//
//  VaultMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainScreen: View {
    @ObservedObject var vault: Vault
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var showCopyNotification = false
    @State private var copyNotificationText = ""
    @State private var scrollOffset: CGFloat = 0
    @State var showBalanceInHeader: Bool = false
    @State var showChainSelection: Bool = false
    @State var showSearchHeader: Bool = false
    @State var focusSearch: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    
    private let scrollReferenceId = "vaultMainScreenBottomContentId"
    
    private let contentInset: CGFloat = 78
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                OffsetObservingScrollView(showsIndicators: false, contentInset: contentInset, scrollOffset: $scrollOffset) {
                    VStack(spacing: 20) {
                        topContentSection
                        Separator(color: Theme.colors.borderLight, opacity: 1)
                        bottomContentSection
                    }
                    .padding(.horizontal, 16)
                }
                .onLoad {
                    scrollProxy = proxy
                }
            }
            header
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .refreshable {
            if let vault = homeViewModel.selectedVault {
                viewModel.updateBalance(vault: vault)
            }
        }
        .background(VaultMainScreenBackground())
        .overlay(
            NotificationBannerView(
                text: copyNotificationText,
                isVisible: $showCopyNotification
            ).showIf(showCopyNotification)
            .zIndex(2)
        )
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
        .sheet(isPresented: $showChainSelection) {
            VaultSelectChainScreen(
                vault: homeViewModel.selectedVault ?? .example,
                isPresented: $showChainSelection
            )
        }
    }
    
    var header: some View {
        VaultMainHeaderView(
            vault: vault,
            showBalance: $showBalanceInHeader,
            vaultSelectorAction: onVaultSelector,
            settingsAction: onSettings
        )
    }
    
    var topContentSection: some View {
        VStack(spacing: 32) {
            VaultMainBalanceView(vault: vault)
            CoinActionsView(
                actions: viewModel.availableActions,
                onAction: onAction
            )
            VaultBannerView(
                title: "signFasterThanEverBefore".localized,
                subtitle: "upgradeYourVaultNow".localized,
                buttonTitle: "upgradeNow".localized,
                bgImage: "referral-banner-2",
                action: onBannerAction,
                onClose: onBannerClose
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
                onAction: onChainAction,
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
            CircularAccessoryIconButton(icon: "write") {
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
        // TODO: - Add vault selector in upcoming PRs
    }
    
    func onSettings() {
        // TODO: - Add settings in upcoming PRs
    }
    
    func onAction(_ action: CoinAction) {
        // TODO: - Add action in upcoming PRs
    }
    
    func onBannerAction() {
        // TODO: - Add banner action in upcoming PRs
    }
    
    func onBannerClose() {
        // TODO: - Add banner close in upcoming PRs
    }
    
    func onSearch() {
        // TODO: - Add search in upcoming PRs
    }
    
    func onCopy(_ group: GroupedChain) {
        ClipboardManager.copyToClipboard(group.address)
        
        copyNotificationText = String(format: "coinAddressCopied".localized, group.name)
        showCopyNotification = true
    }
    
    func onChainAction(_ group: GroupedChain) {
        // TODO: - Add chain action in upcoming PRs
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
}

#Preview {
    VaultMainScreen(vault: .example)
        .environmentObject(HomeViewModel())
        .environmentObject(VaultDetailViewModel())
}
