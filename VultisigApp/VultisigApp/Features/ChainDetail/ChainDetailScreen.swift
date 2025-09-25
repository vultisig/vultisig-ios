//
//  ChainDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailScreen: View {
    // TODO: - Remove after new manage assets is done
    enum SheetType: Int, Identifiable {
        case tokenSelection = 1
        case customToken = 2
        
        var id: Int {
            return self.rawValue
        }
    }
    
    @ObservedObject var group: GroupedChain
    let vault: Vault
    @State var vaultAction: VaultAction?
    
    @StateObject var viewModel: ChainDetailViewModel
    
    @State private var addressToCopy: GroupedChain?
    @State var showManageAssets: Bool = false
    @State var showSearchHeader: Bool = false
    @State var coinToShow: Coin?
    @State var focusSearch: Bool = false
    @State var showReceiveSheet: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    @State var sheetType: SheetType? = nil
    @StateObject var sendTx = SendTransaction()
    
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
        .withAddressCopy(group: $addressToCopy)
        .sheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(groupedChain: group, isPresented: $showReceiveSheet)
        }
        // TODO: - Remove after new manage assets is done
        .sheet(isPresented: Binding<Bool>(
            get: { sheetType != nil },
            set: { newValue in
                if !newValue {
                    sheetType = nil
                }
            }
        )) {
            if let sheetType = sheetType {
                switch sheetType {
                case .tokenSelection:
                    NavigationView {
                        TokenSelectionView(
                            chainDetailView: self,
                            vault: vault,
                            group: group
                        )
                    }
                case .customToken:
                    NavigationView {
                        CustomTokenView(
                            chainDetailView: self,
                            vault: vault,
                            group: group
                        )
                    }
                }
            }
        }
        .onLoad {
            viewModel.refresh(group: group)
        }
        .navigationDestination(item: $vaultAction) {
            VaultActionRouteBuilder().buildActionRoute(action: $0, sendTx: sendTx, vault: vault)
        }
        .navigationDestination(item: $coinToShow) {
            CoinDetailView(coin: $0, group: group, vault: vault, sendTx: sendTx)
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
                coinToShow = $0
            } onManageTokens: {
                sheetType = .tokenSelection
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
                sheetType = .tokenSelection
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
    
    func onExplorer() {
        if
            let url = Endpoint.getExplorerByAddressURLByGroup(chain: group.coins.first?.chain, address: group.address),
            let linkURL = URL(string: url)
        {
            openURL(linkURL)
        }
    }
    
    // TODO: - Remove after new manage assets is done
    func chooseTokensButton(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(text)
            Spacer()
        }
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.bgButtonPrimary)
        .padding(.bottom, 32)
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
        var vaultAction: VaultAction?
        switch action {
        case .receive:
            showReceiveSheet = true
            return
        case .send:
            vaultAction = .send(coin: group.nativeCoin, hasPreselectedCoin: false)
        case .swap:
            guard let fromCoin = viewModel.tokens.first else { return }
            vaultAction = .swap(fromCoin: fromCoin)
        case .deposit, .bridge, .memo:
            vaultAction = .function(coin: group.nativeCoin)
        case .buy:
            vaultAction = .buy(
                address: group.nativeCoin.address,
                blockChainCode: group.nativeCoin.chain.banxaBlockchainCode,
                coinType: group.nativeCoin.ticker
            )
        case .sell:
            // TODO: - To add
            break
        }
        
        guard let vaultAction else { return }
        self.vaultAction = vaultAction
    }
    
    func onCopy() {
        addressToCopy = group
    }
}

#if os(macOS)
extension ChainDetailScreen {
    func container<Content: View>(content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
            HStack {
                Spacer()
                CircularIconButton(icon: "square-3d", action: onExplorer)
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
                    ToolbarButton(image: "cube", action: onExplorer)
                }
            }
    }
}
#endif

#Preview {
    ChainDetailScreen(
        group: .example,
        vault: .example
    )
}
