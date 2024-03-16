//
//  SendCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct SendCryptoView: View {
    @ObservedObject var tx: SendTransaction
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("send", comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: 0.25)
                .padding(.top, 30)
            SendCryptoDetailsView(tx: tx)
        }
    }
}

#Preview {
    SendCryptoView(tx: SendTransaction())
}
