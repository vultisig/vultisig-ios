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

    @StateObject var tokenViewModel = TokenSelectionViewModel()
    @EnvironmentObject var coinViewModel: CoinSelectionViewModel

    var body: some View {
        ZStack {
            Background()
            view

            if tokenViewModel.isLoading {
                Loader()
            }
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
        .searchable(text: $tokenViewModel.searchText)
    }
    
    var view: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(tokenViewModel.filteredTokens, id: \.self) { token in
                    TokenSelectionCell(chain: group.chain, address: address, asset: token, tokenSelectionViewModel: tokenViewModel)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    var address: String {
        return vault.coins.first(where: { $0.chain == group.chain })?.address ?? .empty
    }

    private func saveAssets() {
        Task {
            await coinViewModel.saveAssets(for: vault)
        }
    }
}
