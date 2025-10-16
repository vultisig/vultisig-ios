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
    var onCoinAction: (VaultAction) -> Void

    @State var showReceiveSheet: Bool = false
    
    @StateObject var viewModel: CoinDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    init(coin: Coin, vault: Vault, group: GroupedChain, sendTx: SendTransaction, onCoinAction: @escaping (VaultAction) -> Void) {
        self.coin = coin
        self.vault = vault
        self.group = group
        self.sendTx = sendTx
        self._viewModel = StateObject(wrappedValue: .init(coin: coin))
        self.onCoinAction = onCoinAction
    }
    
    var body: some View {
        GeometryReader { proxy in
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
            .padding(.top, 45)
            .padding(.horizontal, 24)
            .background(ModalBackgroundView(width: proxy.size.width))
            .onLoad(perform: viewModel.setup)
            .onAppear(perform: onAppear)
        }
        .presentationDetents([isIPadOS ? .large : .medium])
        .presentationBackground(Theme.colors.bgSecondary)
        .presentationDragIndicator(.visible)
        .applySheetSize()
        .crossPlatformSheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(
                coin: coin,
                isNativeCoin: false
            ) {
                showReceiveSheet = false
            }
        }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: true)
    }
}

private extension CoinDetailScreen {
    func onAppear() {
        Task {
            await BalanceService.shared.updateBalance(for: coin)
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
        onCoinAction: { _ in}
    )
}
