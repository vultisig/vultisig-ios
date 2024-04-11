//
//  TokenSelectionView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct TokenSelectionView: View {
    @Binding var showTokenSelectionSheet: Bool
    let vault: Vault
    let group: GroupedChain
    
    @State var tokens: [Coin] = []
    
    @EnvironmentObject var viewModel: TokenSelectionViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackSheetButton(showSheet: $showTokenSelectionSheet)
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
                ForEach(tokens, id: \.self) { token in
                    TokenSelectionCell(asset: token)
                }
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 16)
    }
    
    private func setData() {
        viewModel.setData(for: vault)
        tokens = viewModel.groupedAssets[group.name] ?? []
    }
    
    private func saveAssets() {
        viewModel.saveAssets(for: vault)
    }
}

#Preview {
    TokenSelectionView(showTokenSelectionSheet: .constant(true), vault: Vault.example, group: GroupedChain.example)
        .environmentObject(TokenSelectionViewModel())
}
