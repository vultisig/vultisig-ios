//
//  ChainSelectionView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
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
    }
    
    var main: some View {
        VStack {
            headerMac
            content
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "chooseChains")
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(viewModel.groupedAssets.keys.sorted(), id: \.self) { key in
                    ChainSelectionCell(
                        assets: viewModel.groupedAssets[key] ?? [],
                        showAlert: $showAlert
                    )
                }
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .padding(.horizontal, 16)
        }
    }
}
#endif
