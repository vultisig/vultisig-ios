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
    
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var addressToCopy: GroupedChain?
    @State private var scrollOffset: CGFloat = 0
    @State var showBalanceInHeader: Bool = false
    @State var showVaultSelector: Bool = false
    @State var showCreateVault: Bool = false
    @State var showChainSelection: Bool = false
    @State var showSearchHeader: Bool = false
    @State var focusSearch: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    @State private var presentedChainDetail: GroupedChain?
    
    private let scrollReferenceId = "vaultMainScreenBottomContentId"
    
    private let contentInset: CGFloat = 78
    
    var body: some View {
        VStack {
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
            .withAddressCopy(group: $addressToCopy)
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
            .navigationDestination(isPresented: $showCreateVault) {
                CreateVaultView(selectedVault: nil, showBackButton: true)
            }
            .sheet(isPresented: $showVaultSelector) {
                VaultSelectorBottomSheet {
                    showVaultSelector.toggle()
                    showCreateVault.toggle()
                } onSelectVault: { vault in
                    showVaultSelector.toggle()
                    homeViewModel.setSelectedVault(vault)
                }
            }
            .sheet(isPresented: $showChainSelection) {
                VaultSelectChainScreen(
                    vault: homeViewModel.selectedVault ?? .example,
                    isPresented: $showChainSelection
                )
            }
        }
        .navigationDestination(item: $presentedChainDetail) {
            ChainDetailScreen(group: $0, vault: vault)
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
        showVaultSelector.toggle()
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
        addressToCopy = group
    }
    
    func onChainAction(_ group: GroupedChain) {
        presentedChainDetail = group
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
