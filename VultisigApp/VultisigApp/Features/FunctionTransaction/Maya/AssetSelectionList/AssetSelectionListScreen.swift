//
//  AssetSelectionListScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

struct AssetSelectionListScreen: View {
    @Binding var isPresented: Bool
    @Binding var selectedAsset: THORChainAsset?
    var onSelect: () -> Void
    @StateObject var viewModel: AssetSelectionListViewModel

    init(
        isPresented: Binding<Bool>,
        selectedAsset: Binding<THORChainAsset?>,
        dataSource: AssetSelectionDataSource,
        onSelect: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self._selectedAsset = selectedAsset
        self._viewModel = .init(wrappedValue: AssetSelectionListViewModel(dataSource: dataSource))
        self.onSelect = onSelect
    }

    var body: some View {
        Screen(title: "selectAsset".localized, showsBackButton: false) {
            VStack(spacing: 8) {
                SearchTextField(value: $viewModel.searchText)
                ScrollView {
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.filteredAssets.isEmpty {
                        list
                    } else {
                        emptyMessage
                    }
                }
                .cornerRadius(12)
            }
        } toolbarItems: {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
        }
        .applySheetSize()
        .sheetStyle()
        .onDisappear { viewModel.searchText = "" }
        .onLoad {
            Task {
                await viewModel.setup()
            }
        }
    }

    var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredAssets, id: \.asset) { asset in
                SwapCoinCell(coin: asset.asset, balance: nil, balanceFiat: nil, isSelected: selectedAsset == asset) {
                    selectedAsset = asset
                    onSelect()
                }
            }
        }
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)

            Text(NSLocalizedString("loading", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }

    var emptyMessage: some View {
        ErrorMessage(text: "noResultFound")
            .padding(.top, 48)
    }
}

#Preview {
    AssetSelectionListScreen(
        isPresented: .constant(true),
        selectedAsset: .constant(THORChainAsset(thorchainAsset: "THOR.THOR", asset: .example)),
        dataSource: MayaAssetsDataSource()
    ) {}
}
