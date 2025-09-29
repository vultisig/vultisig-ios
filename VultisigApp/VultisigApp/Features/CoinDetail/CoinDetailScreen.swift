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

    @StateObject var viewModel: CoinDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    init(coin: Coin, vault: Vault, group: GroupedChain) {
        self.coin = coin
        self.vault = vault
        self.group = group
        self._viewModel = StateObject(wrappedValue: .init(coin: coin))
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
            .overlay(macOSOverlay)
            .onLoad(perform: viewModel.setup)
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.colors.bgSecondary)
        .presentationDragIndicator(.visible)
        .applySheetHeight()
    }
    
    @ViewBuilder
    var macOSOverlay: some View {
        #if os(macOS)
        VStack(alignment: .trailing) {
            CircularIconButton(icon: "x") {
                dismiss()
            }
            .padding(16)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        #else
        EmptyView()
        #endif
    }
}

private extension CoinDetailScreen {
    func onAction(_ action: CoinAction) {
        
    }
}

#Preview {
    CoinDetailScreen(
        coin: .example,
        vault: .example,
        group: .example
    )
}
