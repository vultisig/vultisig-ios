//
//  ChainSelectionView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension ChainSelectionView {
    var content: some View {
        ZStack {
            ZStack {
                Background()
                main
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chooseChains", comment: "Choose Chains"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showChainSelectionSheet)
            }
        }
    }
    
    var main: some View {
        views
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                searchBar

                ForEach(viewModel.filteredChains, id: \.self) { key in
                    ChainSelectionCell(
                        assets: viewModel.groupedAssets[key] ?? [],
                        showAlert: $showAlert
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0)
            .padding(.horizontal, 16)
        }
    }
}
#endif
