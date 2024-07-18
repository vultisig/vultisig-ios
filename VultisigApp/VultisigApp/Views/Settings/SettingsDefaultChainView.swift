//
//  SettingsDefaultChainView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI

struct SettingsDefaultChainView: View {
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var assets = [CoinMeta]()
    
    @StateObject var viewModel = SettingsDefaultChainViewModel()
    
    var body: some View {
        VStack {
            search
            cells
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
    
    var search: some View {
        Text("Search")
    }
    
    var cells: some View {
        ScrollView {
            ForEach(coinSelectionViewModel.groupedAssets.keys.sorted(), id: \.self) { key in
                let asset = coinSelectionViewModel.groupedAssets[key]?.first
                ToggleSelectionCell(asset: asset, assets: $assets)
            }
        }
    }
    
    private func setData() {
        guard let vault = homeViewModel.selectedVault else {
            return
        }
        
        coinSelectionViewModel.setData(for: vault)
    }
}

#Preview {
    SettingsDefaultChainView()
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
