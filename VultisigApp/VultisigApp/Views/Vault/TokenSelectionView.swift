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

    @EnvironmentObject var tokenViewModel: TokenSelectionViewModel
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel

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
        .task {
            try? await tokenViewModel.loadData(chain: group.chain)
        }
        .onDisappear {
            saveAssets()
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(tokenViewModel.tokens, id: \.self) { token in
                    TokenSelectionCell(chain: group.chain, asset: token)
                }
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 16)
    }
    
    private func saveAssets() {
        Task {
            await coinViewModel.saveAssets(for: vault)
        }
    }
}
