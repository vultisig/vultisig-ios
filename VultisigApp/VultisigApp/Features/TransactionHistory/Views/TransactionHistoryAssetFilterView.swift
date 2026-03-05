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
            title: "",
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

        return Button {
            if isSelected {
                viewModel.selectedAssetFilters.remove(coin.ticker)
            } else {
                viewModel.selectedAssetFilters.insert(coin.ticker)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImageView(
                        logo: coin.logo,
                        size: CGSize(width: 40, height: 40),
                        ticker: coin.ticker,
                        tokenChainLogo: coin.chainLogo
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.colors.alertSuccess)
                            .background(Circle().fill(Theme.colors.bgPrimary).frame(width: 16, height: 16))
                    }
                }

                Text(coin.ticker)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 70, height: 70)
            .background(
                isSelected
                    ? Theme.colors.primaryAccent4.opacity(0.1)
                    : Theme.colors.bgSurface1
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Theme.colors.primaryAccent4 : Theme.colors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
