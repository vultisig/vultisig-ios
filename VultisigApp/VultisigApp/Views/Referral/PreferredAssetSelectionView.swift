//
//  PreferredAssetSelectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

struct PreferredAssetSelectionView: View {
    @Binding var preferredAsset: CoinMeta?
    
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
            ForEach(viewModel.filteredAssets, id: \.self) { asset in
                SwapCoinCell(coin: asset, balance: nil, balanceFiat: nil, isSelected: preferredAsset == asset) {
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
    PreferredAssetSelectionView(preferredAsset: .constant(.example))
}


class PreferredAssetSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published private var assets: [CoinMeta] = []
    private let thorchainService: THORChainAPIService
    
    init(thorchainService: THORChainAPIService = .init()) {
        self.thorchainService = thorchainService
    }
    
    var filteredAssets: [CoinMeta] {
        guard searchText.isNotEmpty else { return assets }
        return assets.filter { $0.ticker.localizedCaseInsensitiveContains(searchText) }
    }
    
    func setup() async {
        await MainActor.run { isLoading = true }
        do {
            let pools = try await thorchainService.getPools()
            let assets: [CoinMeta] = pools.compactMap { pool -> CoinMeta? in
                let splitAsset = pool.asset.split(separator: ".")
                
                let chain = String(splitAsset[safe: 0] ?? "")
                let asset = splitAsset[safe: 1]
                var symbol = chain
                var contractAddress = ""
                
                if let asset, asset.contains("-") {
                    let split = asset.split(separator: "-")
                    symbol = String(split[0])
                    contractAddress = String(split[1])
                }
                
                let appChain = Chain.allCases.first { $0.swapAsset == chain }
                guard let appChain else { return nil }
                
                return CoinMeta(
                    chain: appChain,
                    ticker: symbol.uppercased(),
                    logo: symbol.lowercased(),
                    decimals: pool.decimals ?? 6,
                    priceProviderId: "",
                    contractAddress: contractAddress,
                    isNativeToken: contractAddress.isEmpty
                )
            }
            await MainActor.run { self.assets = assets }
        } catch {
            // TODO: - Add error handling
            print(error)
        }
        await MainActor.run { isLoading = false }
    }
}
