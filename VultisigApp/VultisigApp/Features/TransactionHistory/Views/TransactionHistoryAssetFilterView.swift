//
//  TransactionHistoryAssetFilterView.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryAssetFilterView: View {
    @ObservedObject var viewModel: TransactionHistoryViewModel
    @Binding var isPresented: Bool

    var sections: [AssetSection<Int, TransactionHistoryCoinAsset>] {
        let coins = viewModel.filteredAvailableCoins
        return coins.isEmpty ? [] : [AssetSection(assets: coins)]
    }

    var body: some View {
        AssetSelectionContainerSheet(
            title: "searchAsset".localized,
            isPresented: $isPresented,
            searchText: $viewModel.filterSearchText,
            elements: sections,
            onSave: { isPresented = false },
            cellBuilder: cellBuilder,
            emptyStateBuilder: {
                ActionBannerView(
                    icon: "calendar-days",
                    title: "noTransactionsYet".localized,
                    subtitle: "noTransactionsYetSubtitle".localized,
                    buttonTitle: "",
                    showsActionButton: false,
                    action: {}
                )
            }
        )
    }

    func cellBuilder(_ coin: TransactionHistoryCoinAsset, _: Int) -> some View {
        let isSelected = viewModel.selectedAssetFilters.contains(coin.ticker)

        return AssetSelectionGridCell(
            name: coin.ticker,
            ticker: coin.ticker,
            logo: coin.logo,
            tokenChainLogo: coin.chainLogo,
            isSelected: Binding(
                get: { isSelected },
                set: { _ in }
            ),
            onSelection: {
                if isSelected {
                    viewModel.selectedAssetFilters.remove(coin.ticker)
                } else {
                    viewModel.selectedAssetFilters.insert(coin.ticker)
                }
            }
        )
    }
}
