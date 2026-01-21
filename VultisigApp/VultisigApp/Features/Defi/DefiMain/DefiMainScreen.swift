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
    @Binding var showBalanceInHeader: Bool

    // Logic/State for Circle presence check
    private var isCircleEnabled: Bool {
        // Feature flag or simply always enabled as per requirements
        return true
    }

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router

    @State var scrollProxy: ScrollViewProxy?
    @State var showSearchHeader: Bool = false
    @State var focusSearch: Bool = false
    @State var scrollOffset: CGFloat = 0
    @State var showChainSelection: Bool = false

    private let scrollReferenceId = "DefiMainScreenBottomContentId"
    private let contentInset: CGFloat = 78
    private let horizontalPadding: CGFloat = 16

    @StateObject var viewModel = DefiMainViewModel()

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                VaultMainScreenScrollView(
                    showsIndicators: false,
                    contentInset: contentInset,
                    scrollOffset: $scrollOffset
                ) {
                    LazyVStack(spacing: 20) {
                        DefiMainBalanceView(vault: vault)
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
            .background(VaultMainScreenBackground())
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
                DefiSelectChainScreen(
                    vault: vault,
                    isPresented: $showChainSelection
                ) { refresh() }
            }
            .refreshable { refresh() }
            .onChange(of: settingsViewModel.selectedCurrency) {
                refresh()
            }
            .onChange(of: scrollOffset) { _, newValue in
                onScrollOffsetChange(newValue)
            }
        }
        .throttledOnAppear(interval: 15.0, action: refresh)
        .onChange(of: vault) { _, _ in
            refresh()
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

            DefiChainListView(
                vault: vault,
                viewModel: viewModel,
                onCustomizeChains: onCustomizeChains
            )
            VStack {}
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

    func refresh() {
        viewModel.groupChains(vault: vault)
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

    func onScrollOffsetChange(_ offset: CGFloat) {
        let showBalanceInHeader: Bool = offset < contentInset
        guard showBalanceInHeader != self.showBalanceInHeader else { return }
        self.showBalanceInHeader = showBalanceInHeader
    }
}

#Preview {
    DefiMainScreen(
        vault: .example,
        showBalanceInHeader: .constant(false)
    )
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
}
