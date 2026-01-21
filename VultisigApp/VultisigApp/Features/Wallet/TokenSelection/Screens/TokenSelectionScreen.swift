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

    var sections: [AssetSection<Int, TokenSelectionAsset>] {
        !elements.isEmpty ? [AssetSection(assets: elements)] : []
    }

    var body: some View {
        AssetSelectionContainerSheet(
            title: "selectTokensTitle".localized,
            subtitle: "selectTokensSubtitle".localized,
            isPresented: $isPresented,
            searchText: $tokenViewModel.searchText,
            elements: sections,
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
        .onReceive(tokenViewModel.$searchText) { _ in
            tokenViewModel.updateSearchedTokens(groupedChain: group)
        }
    }

    @ViewBuilder
    func cellBuilder(_ asset: TokenSelectionAsset, _ index: Int) -> some View {
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

    func onSave() {
        Task {
            await CoinService.saveAssets(for: vault, selection: coinViewModel.selection)
            await MainActor.run { isPresented = false }
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
