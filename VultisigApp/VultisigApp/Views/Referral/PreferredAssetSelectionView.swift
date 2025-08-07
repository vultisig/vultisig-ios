//
//  PreferredAssetSelectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

struct PreferredAssetSelectionView: View {
    @Binding var preferredAsset: PreferredAsset?
    
    @StateObject var viewModel = PreferredAssetSelectionViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Screen(title: "selectAssset".localized) {
            VStack(spacing: 12) {
                SearchTextField(value: $viewModel.searchText, isFocused: .init())
                ScrollView {
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.filteredAssets.isEmpty {
                        list
                    } else {
                        emptyMessage
                    }
                }
            }
        }
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
                    dismiss()
                }
            }
        }
        .cornerRadius(12)
    }
    
    var loadingView: some View {
        VStack(spacing: 16) {
            SpinningLineLoader()
                .scaleEffect(1.2)
            
            Text(NSLocalizedString("loading", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.extraLightGray)
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
    PreferredAssetSelectionView(preferredAsset: .constant(PreferredAsset(thorchainAsset: ".", asset: .example)))
}
