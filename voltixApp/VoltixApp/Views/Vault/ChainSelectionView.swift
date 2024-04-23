//
//  ChainSelectionView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct ChainSelectionView: View {
    @Binding var showChainSelectionSheet: Bool
    let vault: Vault
    
    @EnvironmentObject var viewModel: TokenSelectionViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chooseChains", comment: "Choose Chains"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackSheetButton(showSheet: $showChainSelectionSheet)
            }
        }
        .onAppear {
            setData()
        }
        .onChange(of: vault) {
            setData()
        }
        .onDisappear {
            saveAssets()
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(viewModel.groupedAssets.keys.sorted(), id: \.self) { key in
                    ChainSelectionCell(assets: viewModel.groupedAssets[key] ?? [])
                }
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 16)
    }
    
    private func setData() {
        viewModel.setData(for: vault)
    }
    
    private func saveAssets() {
        viewModel.saveAssets(for: vault)
    }
}

#Preview {
    ChainSelectionView(showChainSelectionSheet: .constant(true), vault: Vault.example)
        .environmentObject(TokenSelectionViewModel())
}
