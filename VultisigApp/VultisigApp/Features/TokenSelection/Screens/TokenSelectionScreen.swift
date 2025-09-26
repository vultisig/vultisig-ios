//
//  TokenSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

enum TokenSelectionAsset: Hashable {
    case custom
    case token(CoinMeta)
}

struct TokenSelectionScreen: View {
    let vault: Vault
    let group: GroupedChain
    @Binding var isPresented: Bool
    var onCustomToken: () -> Void
    
    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel
    
    var elements: [TokenSelectionAsset] {
        let assets = tokenViewModel.searchText.isEmpty ?
            tokenViewModel.selectedTokens + tokenViewModel.preExistTokens :
            tokenViewModel.searchedTokens
        return [.custom] + assets.map { .token($0) }
    }
    
    var body: some View {
        AssetSelectionContainerScreen(
            title: "selectTokensTitle".localized,
            subtitle: "selectTokensSubtitle".localized,
            isPresented: $isPresented,
            searchText: $tokenViewModel.searchText,
            elements: elements,
            onSave: onSave,
            cellBuilder: cellBuilder,
            emptyStateBuilder: { EmptyView() }
        )
        .onAppear {
            tokenViewModel.loadData(groupedChain: group)
        }
        .onDisappear {
            tokenViewModel.cancelLoading()
        }
        .onReceive(tokenViewModel.$searchText) { newVault in
            tokenViewModel.updateSearchedTokens(groupedChain: group)
        }
    }
    
    @ViewBuilder
    func cellBuilder(_ asset: TokenSelectionAsset) -> some View {
        switch asset {
        case .custom:
            CustomTokenGridCell(action: onCustomToken)
        case .token(let coin):
            TokenSelectionGridCell(
                coin: coin,
                isSelected: coinViewModel.isSelected(asset: coin)
            ) {
                coinViewModel.handleSelection(isSelected: $0, asset: coin)
            }
        }
    }
    
    func isTokenSelected(asset: CoinMeta) -> Binding<Bool> {
        return Binding(get: {
            return coinViewModel.isSelected(asset: asset)
        }) { newValue in
            coinViewModel.handleSelection(isSelected: newValue, asset: asset)
        }
    }
    
    func onSave() {
        Task {
            await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
            await MainActor.run { isPresented.toggle() }
        }
    }
}

#Preview {
    TokenSelectionScreen(
        vault: .example,
        group: .example,
        isPresented: .constant(true),
        onCustomToken: {}
    )
}
