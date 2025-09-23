//
//  ChainDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailScreen: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    
    @StateObject var viewModel: ChainDetailViewModel
    
    @State private var showCopyNotification = false
    @State private var copyNotificationText = ""
    @State var showManageAssets: Bool = false
    @State var showSearchHeader: Bool = false
    @State var focusSearch: Bool = false
    @State var showReceiveSheet: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    
    private let scrollReferenceId = "chainDetailScreenBottomContentId"
    
    @Environment(\.openURL) var openURL
    
    init(group: GroupedChain, vault: Vault) {
        self.group = group
        self.vault = vault
        self._viewModel = StateObject(wrappedValue: ChainDetailViewModel(vault: vault, group: group))
    }
    
    var body: some View {
        container {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        topContentSection
                        bottomContentSection
                    }
                    .padding(.horizontal, 16)
                }
                .onLoad {
                    scrollProxy = proxy
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .refreshable {
                viewModel.refresh(group: group)
            }
            .background(VaultMainScreenBackground())
        }
        .overlay(
            NotificationBannerView(
                text: copyNotificationText,
                isVisible: $showCopyNotification
            ).showIf(showCopyNotification)
            .zIndex(2)
        )
        .sheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(groupedChain: group, isPresented: $showReceiveSheet)
        }
        .onLoad {
            viewModel.refresh(group: group)
        }
    }
    
    var topContentSection: some View {
        VStack(spacing: 32) {
            ChainDetailHeaderView(vault: vault, group: group, onCopy: onCopy)
            CoinActionsView(
                actions: viewModel.availableActions,
                onAction: onAction
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
            
            ChainDetailListView(viewModel: viewModel) {
                // TODO: - On Press
            } onManageTokens: {
                // TODO: - On Manage
            }
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
                showManageAssets.toggle()
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
    
    var explorerButton: some View {
        CircularIconButton(icon: "square-3d") {
            if
                let url = Endpoint.getExplorerByAddressURLByGroup(chain: group.coins.first?.chain, address: group.address),
                let linkURL = URL(string: url)
            {
                openURL(linkURL)
            }
        }
    }
}

private extension ChainDetailScreen {
    func toggleSearch() {
        withAnimation(.interpolatingSpring) {
            showSearchHeader.toggle()
        }
        
        if showSearchHeader {
            focusSearch.toggle()
        }
    }
    
    func clearSearch() {
        viewModel.searchText = ""
        toggleSearch()
    }
    
    func onAction(_ action: CoinAction) {
        switch action {
        case .receive:
            showReceiveSheet = true
        default:
            // TODO: - Add action
            break
        }
    }
    
    func onCopy() {
        ClipboardManager.copyToClipboard(group.address)
        
        copyNotificationText = String(format: "coinAddressCopied".localized, group.name)
        showCopyNotification = true
    }
}

#if os(macOS)
extension ChainDetailScreen {
    func container<Content: View>(content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
            HStack {
                Spacer()
                explorerButton
            }
            .padding(.horizontal, 24)
            .frame(height: 40)
        }
    }
}
#else
extension ChainDetailScreen {
    func container<Content: View>(content: () -> Content) -> some View {
        content()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    explorerButton
                }
            }
    }
}
#endif

#Preview {
    ChainDetailScreen(group: .example, vault: .example)
}
