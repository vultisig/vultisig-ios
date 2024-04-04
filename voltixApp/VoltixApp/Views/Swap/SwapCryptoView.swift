//
//  SwapCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {

    @StateObject var viewModel = SwapCryptoViewModel()

    let coin: Coin
    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("swap", comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .task {
            try? await viewModel.load(fromCoin: coin, coins: vault.coins)
        }
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: viewModel.progress)
                .padding(.top, 30)
            SwapCryptoDetailsView(viewModel: viewModel)
        }
    }
}

#Preview {
    SwapCryptoView(coin: .example, vault: .example)
}
