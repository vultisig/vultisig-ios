//
//  SendDetailsAssetTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct SendDetailsAssetTab: View {
    let isShown: Bool
    let transition: AnyTransition
    let horizontalInset: CGFloat
    @Bindable var viewModel: SendDetailsViewModel

    var body: some View {
        content
            .onChange(of: isShown) { oldValue, newValue in
                guard oldValue, !newValue else { return }
                viewModel.assetSetupDone = true
            }
    }

    var content: some View {
        VStack(spacing: 0) {
            if isShown {
                SendAssetStepView(
                    vault: viewModel.vault,
                    selectedCoin: viewModel.coin,
                    filter: $viewModel.assetFilter,
                    searchText: $viewModel.assetSearchText,
                    horizontalInset: horizontalInset,
                    onSelect: select
                )
                .transition(transition)
            }
        }
    }

    private func select(_ coin: Coin) {
        viewModel.fromAddress = coin.address
        viewModel.coin = coin
        viewModel.assetSetupDone = true
        viewModel.onSelect(tab: .address)
    }
}
