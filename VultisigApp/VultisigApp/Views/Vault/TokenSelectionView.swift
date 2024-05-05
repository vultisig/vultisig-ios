//
//  TokenSelectionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct TokenSelectionView: View {
    @Binding var showTokenSelectionSheet: Bool
    let vault: Vault
    let group: GroupedChain
    let tokens: [Coin]
    
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
        .onDisappear {
            saveAssets()
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(tokens, id: \.self) { token in
                    TokenSelectionCell(asset: token)
                }
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 16)
    }
    
    private func saveAssets() {
        viewModel.saveAssets(for: vault)
    }
}

#Preview {
    TokenSelectionView(showTokenSelectionSheet: .constant(true), vault: Vault.example, group: GroupedChain.example, tokens: [])
        .environmentObject(TokenSelectionViewModel())
}
