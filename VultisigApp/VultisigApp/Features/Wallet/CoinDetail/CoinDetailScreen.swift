//
//  CoinDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import SwiftUI

struct CoinDetailScreen: View {
    let coin: Coin
    let vault: Vault
    @ObservedObject var group: GroupedChain
    @ObservedObject var sendTx: SendTransaction
    @Binding var isPresented: Bool
    var onCoinAction: (VaultAction) -> Void

    @State var showReceiveSheet: Bool = false
    @State var addressToCopy: Coin?

    @StateObject var viewModel: CoinDetailViewModel

    @Environment(\.openURL) var openURL
    
    init(
        coin: Coin,
        vault: Vault,
        group: GroupedChain,
        sendTx: SendTransaction,
        isPresented: Binding<Bool>,
        onCoinAction: @escaping (VaultAction) -> Void
    ) {
        self.coin = coin
        self.vault = vault
        self.group = group
        self.sendTx = sendTx
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: .init(coin: coin))
        self.onCoinAction = onCoinAction
    }
    
    var body: some View {
        container
    }
    
    var container: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
            .presentationSizingFitted()
            .applySheetSize()
            .transaction { $0.disablesAnimations = true }
#endif
    }
    
    var content: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    CoinDetailHeaderView(coin: coin)
                    CoinActionsView(
                        actions: viewModel.availableActions,
                        onAction: onAction
                    )
                    .padding(.bottom, 8)
                    CoinPriceNetworkView(
                        chainName: group.name,
                        price: Decimal(coin.price).formatToFiat()
                    )
                }
                .padding(.horizontal, 24)
            }
            .background(ModalBackgroundView(width: proxy.size.width))
            .onLoad(perform: viewModel.setup)
            .onAppear(perform: onAppear)
            .withAddressCopy(coin: $addressToCopy)
            .refreshable {
                await refresh()
            }
        }
        .presentationDetents([isIPadOS ? .large : .medium])
        .presentationBackground(Theme.colors.bgSecondary)
        .presentationDragIndicator(.visible)
        .background(Theme.colors.bgSecondary)
        .applySheetSize(700, 450)
        .crossPlatformSheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(
                coin: coin,
                isNativeCoin: false,
                onClose: { showReceiveSheet = false }
            ) { coin in
                showReceiveSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    addressToCopy = coin
                }
            }
        }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            #if os(macOS)
            CustomToolbarItem(placement: .trailing) {
                RefreshToolbarButton(onRefresh: onRefreshButton)
            }
            #endif

            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "square-3d", action: onExplorer)
            }
        }
    }
}

private extension CoinDetailScreen {
    func onAppear() {
        Task {
            await refresh()
        }
    }

    func onRefreshButton() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await BalanceService.shared.updateBalance(for: coin)
    }

    func onExplorer() {
        if
            let url = Endpoint.getExplorerByCoinURL(coin: coin),
            let linkURL = URL(string: url)
        {
            openURL(linkURL)
        }
    }
    
    func onAction(_ action: CoinAction) {
        sendTx.reset(coin: coin)
        var vaultAction: VaultAction?
        switch action {
        case .receive:
            showReceiveSheet = true
        case .send:
            vaultAction = .send(coin: coin, hasPreselectedCoin: true)
        case .swap:
            vaultAction = .swap(fromCoin: coin)
        case .deposit, .bridge, .memo:
            sendTx.coin = coin
            vaultAction = .function(coin: coin)
        case .buy:
            vaultAction = .buy(
                address: coin.address,
                blockChainCode: coin.chain.banxaBlockchainCode,
                coinType: coin.ticker
            )
        case .sell:
            // TODO: - To add
            break
        }
        
        guard let vaultAction else { return }
        onCoinAction(vaultAction)
    }
}

#Preview {
    CoinDetailScreen(
        coin: .example,
        vault: .example,
        group: .example,
        sendTx: .init(),
        isPresented: .constant(true),
        onCoinAction: { _ in}
    )
}
