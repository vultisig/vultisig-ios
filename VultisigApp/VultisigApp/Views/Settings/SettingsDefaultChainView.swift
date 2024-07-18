//
//  SettingsDefaultChainView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI
import SwiftData

struct SettingsDefaultChainView: View {
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
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
        .onChange(of: settingsDefaultChainViewModel.searchText) { oldValue, newValue in
            settingsDefaultChainViewModel.search()
        }
    }
    
    var search: some View {
        Search(searchText: $settingsDefaultChainViewModel.searchText)
            .padding(.top, 30)
            .padding(.horizontal, 16)
    }
    
    var cells: some View {
        ScrollView {
            VStack {
                ForEach(settingsDefaultChainViewModel.filteredAssets, id: \.self) { asset in
                    ToggleSelectionCell(asset: asset, assets: settingsDefaultChainViewModel.defaultChains)
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
        settingsDefaultChainViewModel.setData(coinSelectionViewModel.groupedAssets)
    }
}

#Preview {
    SettingsDefaultChainView()
        .environmentObject(SettingsDefaultChainViewModel())
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
