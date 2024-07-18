//
//  SettingsDefaultChainView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI
import SwiftData

struct SettingsDefaultChainView: View {
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @Query var defaultChains: [CoinMeta]
    
    @StateObject var viewModel = SettingsDefaultChainViewModel()
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("defaultChains", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        VStack {
            search
            cells
        }
        .onChange(of: viewModel.searchText) { oldValue, newValue in
            viewModel.search(coinSelectionViewModel.groupedAssets)
        }
    }
    
    var search: some View {
        Search(searchText: $viewModel.searchText)
            .padding(.top, 30)
            .padding(.horizontal, 16)
    }
    
    var cells: some View {
        ScrollView {
            VStack {
                ForEach(viewModel.filteredAssets.keys.sorted(), id: \.self) { key in
                    let asset = coinSelectionViewModel.groupedAssets[key]?.first
                    ToggleSelectionCell(asset: asset, assets: defaultChains)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 50)
        }
    }
    
    private func setData() {
        guard let vault = homeViewModel.selectedVault else {
            return
        }
        
        coinSelectionViewModel.setData(for: vault)
        viewModel.setData(coinSelectionViewModel.groupedAssets)
    }
}

#Preview {
    SettingsDefaultChainView()
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
