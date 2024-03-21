//
//  SwapCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {
    @ObservedObject var tx: SendTransaction
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
            ProgressBar(progress: 0.25)
                .padding(.top, 30)
            SwapCryptoDetailsView(tx: tx, group: group)
        }
    }
}

#Preview {
    SwapCryptoView(tx: SendTransaction(), group: GroupedChain.example)
}
