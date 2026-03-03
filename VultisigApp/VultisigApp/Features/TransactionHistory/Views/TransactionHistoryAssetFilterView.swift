//
//  TransactionHistoryAssetFilterView.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryAssetFilterView: View {
    @ObservedObject var viewModel: TransactionHistoryViewModel

    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                searchBar
                coinGrid
                applyButton
            }
            .padding(16)
            .background(Theme.colors.bgPrimary)
            .navigationTitle("filterByAsset".localized)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.colors.textTertiary)
            TextField("search".localized, text: $searchText)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
    }

    // MARK: - Coin Grid

    private var coinGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 12)]
        let filteredCoins = viewModel.availableCoins.filter { coin in
            searchText.isEmpty || coin.ticker.localizedCaseInsensitiveContains(searchText)
        }

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredCoins, id: \.ticker) { coin in
                    coinItem(coin)
                }
            }
        }
    }

    private func coinItem(_ coin: (ticker: String, logo: String, chainLogo: String?)) -> some View {
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

    // MARK: - Apply Button

    private var applyButton: some View {
        PrimaryButton(title: "apply") {
            dismiss()
        }
    }
}
