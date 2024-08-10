//
//  SettingsDefaultChainView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-25.
//

import SwiftUI

struct SettingsDefaultChainView: View {
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel

    var body: some View {
        ZStack {
            Background()
            main
            
            if settingsDefaultChainViewModel.showLoader {
                Loader()
            }
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationTitle(NSLocalizedString("defaultChains", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
#endif
    }
    
    var main: some View {
        VStack(spacing: 0) {
#if os(macOS)
            headerMac
#endif
            content
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "defaultChains")
            .padding(.bottom, 8)
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
                ForEach(settingsDefaultChainViewModel.filteredAssets.sorted(by: {
                    $0.chain.name < $1.chain.name
                }), id: \.self) { asset in
                    ToggleSelectionCell(asset: asset, assets: settingsDefaultChainViewModel.defaultChains)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 50)
        }
    }
}

#Preview {
    SettingsDefaultChainView()
        .environmentObject(SettingsDefaultChainViewModel())
}
