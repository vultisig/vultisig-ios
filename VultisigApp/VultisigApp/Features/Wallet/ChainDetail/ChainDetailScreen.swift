//
//  ChainDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailScreen: View {
    @Environment(\.router) var router
    let nativeCoin: Coin
    let vault: Vault
    @Binding var refreshTrigger: Bool
    var onAddressCopy: ((Coin) -> Void)?

    @StateObject var viewModel: ChainDetailViewModel
    @State var showManageTokens: Bool = false
    @State var showSearchHeader: Bool = false
    @State var coinToShow: Coin?
    @State var focusSearch: Bool = false
    @State var showReceiveSheet: Bool = false
    @State var scrollProxy: ScrollViewProxy?

    @StateObject var sendTx = SendTransaction()

    private let scrollReferenceId = "chainDetailScreenBottomContentId"

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(\.dismiss) var dismiss

    var coins: [Coin] {
        vault.coins(for: nativeCoin.chain)
    }

    var groupedChain: GroupedChain {
        return GroupedChain(
            chain: nativeCoin.chain,
            address: nativeCoin.address,
            logo: nativeCoin.chain.logo,
            count: coins.count,
            coins: coins
        )
    }

    init(
        nativeCoin: Coin,
        vault: Vault,
        refreshTrigger: Binding<Bool> = .constant(false),
        onAddressCopy: ((Coin) -> Void)? = nil
    ) {
        self.nativeCoin = nativeCoin
        self.vault = vault
        self._refreshTrigger = refreshTrigger
        self.onAddressCopy = onAddressCopy
        self._viewModel = StateObject(wrappedValue: ChainDetailViewModel(vault: vault, nativeCoin: nativeCoin))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    topContentSection
                        .padding(.top, isMacOS ? 60 : 0)
                    bottomContentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, isMacOS ? 120 : 0)
            }
            .onLoad {
                scrollProxy = proxy
            }
        }
        .refreshable {
            refresh()
        }
        .background(VaultMainScreenBackground())
        .crossPlatformSheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(
                coin: nativeCoin,
                isNativeCoin: true,
                onClose: { showReceiveSheet = false },
                onCopy: { coin in
                    showReceiveSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onAddressCopy?(coin)
                    }
                }
            )
        }
        .crossPlatformSheet(isPresented: $showManageTokens) {
            TokenSelectionContainerScreen(
                vault: vault,
                group: groupedChain,
                isPresented: $showManageTokens
            )
        }
        .onLoad {
            viewModel.refresh()
            refresh()
        }
        .onChange(of: refreshTrigger) { _, _ in
            refresh()
        }
        .crossPlatformSheet(item: $coinToShow) {
            CoinDetailScreen(
                coin: $0,
                vault: vault,
                sendTx: sendTx,
                isPresented: Binding(get: { coinToShow != nil}, set: { _ in coinToShow = nil }),
                onCoinAction: onCoinAction
            )
        }
        .onChange(of: coins) { _, _ in
            refresh()
        }
    }

    var topContentSection: some View {
        VStack(spacing: 32) {
            ChainDetailHeaderView(
                vault: vault,
                nativeCoin: nativeCoin,
                coins: vault.coins(for: nativeCoin.chain),
                onCopy: onCopy
            )
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
                showManageTokens = true
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
            VStack(spacing: 8) {
                Text("tokens".localized)
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
                showManageTokens = true
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
}

private extension ChainDetailScreen {
    func onRefreshButton() {
        refresh()
    }

    func refresh() {
        Task.detached {
            await updateBalances()
            await MainActor.run {
                coinSelectionViewModel.setData(for: vault)
                // Notify viewModel and group to update the tokens list
                viewModel.objectWillChange.send()
            }
        }
    }

    func updateBalances() async {
        let vault = self.vault // Capture on main actor
        let coins = vault.coins.filter { $0.chain == nativeCoin.chain }
        await withTaskGroup(of: Void.self) { taskGroup in
            for coin in coins {
                taskGroup.addTask {
                    await coinSelectionViewModel.loadData(coin: coin)
                    if coin.isNativeToken {
                        await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
                    }
                }
            }
        }
    }

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
        sendTx.reset(coin: nativeCoin)
        var vaultAction: VaultAction?
        switch action {
        case .receive:
            showReceiveSheet = true
            return
        case .send:
            vaultAction = .send(coin: nativeCoin, hasPreselectedCoin: false)
        case .swap:
            guard let fromCoin = viewModel.tokens.first else { return }
            vaultAction = .swap(fromCoin: fromCoin)
        case .deposit, .bridge, .memo:
            if let nativeCoin = viewModel.tokens.first(where: { $0.isNativeToken }) {
                sendTx.reset(coin: nativeCoin)
            } else if let firstCoin = viewModel.tokens.first {
                sendTx.reset(coin: firstCoin)
            }
            vaultAction = .function(coin: nativeCoin)
        case .buy:
            vaultAction = .buy(
                address: nativeCoin.address,
                blockChainCode: nativeCoin.chain.banxaBlockchainCode,
                coinType: nativeCoin.ticker
            )
        case .sell:
            break
        }

        guard let vaultAction else { return }

        navigateToAction(action: vaultAction)
    }

    func onCopy() {
        onAddressCopy?(nativeCoin)
    }

    func onCoinAction(_ action: VaultAction) {
        coinToShow = nil
        navigateToAction(action: action)
    }

    func navigateToAction(action: VaultAction) {
        router.navigate(to: HomeRoute.vaultAction(action: action, sendTx: sendTx, vault: vault))
    }
}

#Preview {
    ChainDetailScreen(
        nativeCoin: .example,
        vault: .example
    )
    .environmentObject(HomeViewModel())
}
