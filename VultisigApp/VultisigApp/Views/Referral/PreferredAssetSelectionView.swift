//
//  PreferredAssetSelectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

struct PreferredAssetSelectionView: View {
    @Binding var isPresented: Bool
    @Binding var preferredAsset: THORChainAsset?
    var onSelect: () -> Void
    @StateObject var viewModel = PreferredAssetSelectionViewModel()
    
    var body: some View {
        Screen(showNavigationBar: false) {
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
        }
        .applySheetSize()
        .sheetStyle()
        .crossPlatformToolbar("selectAsset".localized, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
        }
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
                SwapCoinCell(coin: asset.asset, balance: nil, balanceFiat: nil, isSelected: preferredAsset?.asset == asset.asset) {
                    preferredAsset = asset
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
    PreferredAssetSelectionView(isPresented: .constant(true), preferredAsset: .constant(THORChainAsset(thorchainAsset: ".", asset: .example))) {}
}
