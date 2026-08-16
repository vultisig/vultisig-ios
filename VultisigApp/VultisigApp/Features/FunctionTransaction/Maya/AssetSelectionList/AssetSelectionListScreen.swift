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
        Screen {
            VStack(spacing: 8) {
                SearchTextField(value: $viewModel.searchText)
                ScrollView {
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.filteredAssets.isEmpty {
                        list
                    } else if viewModel.didFailToLoad {
                        failureMessage
                    } else {
                        emptyMessage
                    }
                }
            }
        }
        .screenTitle("selectAsset".localized)
        .screenBackButtonHidden()
        .screenToolbar {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
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

    /// The rounded surface belongs to the rows, not to the scroll viewport. A
    /// `ScrollView` takes the full height it is offered, so rounding the
    /// scroll view put the bottom corners at the bottom of the sheet while the
    /// rows ended higher up with square ones — a list that reads as cut off.
    var list: some View {
        // Read the filtered set once: it is a computed property that filters on
        // every access, and each row needs the count.
        let assets = viewModel.filteredAssets
        return LazyVStack(spacing: 0) {
            ForEach(Array(assets.enumerated()), id: \.element.asset) { index, asset in
                SwapCoinCell(
                    coin: asset.asset,
                    balance: nil,
                    balanceFiat: nil,
                    isSelected: selectedAsset == asset,
                    showsSeparator: false
                ) {
                    selectedAsset = asset
                    onSelect()
                }
                .commonListItemContainer(index: index, itemsCount: assets.count)
            }
        }
        .commonListContainer()
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)

            Text(NSLocalizedString("loading", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }

    var emptyMessage: some View {
        ErrorMessage(text: "noResultFound")
            .padding(.top, 48)
    }

    /// A failed fetch used to render as "no result found", which reads as a
    /// statement about the user's holdings rather than about the network.
    private var failureMessage: some View {
        ErrorMessage(text: "assetsLoadFailed", width: 260)
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
