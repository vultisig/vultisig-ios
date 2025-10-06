//
//  PreferredAssetSelectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

struct PreferredAssetSelectionView: View {
    @Binding var isPresented: Bool
    @Binding var preferredAsset: PreferredAsset?
    var onSelect: () -> Void
    @StateObject var viewModel = PreferredAssetSelectionViewModel()
    
    var body: some View {
        VStack(spacing: 8) {
            SheetHeaderView(title: "selectAsset".localized, isPresented: $isPresented)
                .padding(.top, 8)
                .padding(.bottom, 10)
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
        .fullScreenSheet()
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
                .foregroundColor(Theme.colors.textExtraLight)
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
    PreferredAssetSelectionView(isPresented: .constant(true), preferredAsset: .constant(PreferredAsset(thorchainAsset: ".", asset: .example))) {}
}
