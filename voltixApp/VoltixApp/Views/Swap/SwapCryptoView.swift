//
//  SwapCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {

    @StateObject var swapViewModel = SwapCryptoViewModel()

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var coinViewModel: CoinViewModel

    let group: GroupedChain
    
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
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: swapViewModel.progress)
                .padding(.top, 30)
            SwapCryptoDetailsView(tx: tx, swapViewModel: swapViewModel, coinViewModel: coinViewModel, group: group)
        }
    }
}

#Preview {
    SwapCryptoView(tx: SwapTransaction(), coinViewModel: CoinViewModel(), group: GroupedChain.example)
}
