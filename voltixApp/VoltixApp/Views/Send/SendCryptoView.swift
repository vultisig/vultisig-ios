//
//  SendCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct SendCryptoView: View {
    @ObservedObject var tx: SendTransaction
    
    @StateObject var viewModel = SendCryptoViewModel()
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(viewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                refreshButton
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: viewModel.getProgress())
                .padding(.top, 30)
            tabView
        }
    }
    
    var tabView: some View {
        TabView(selection: $viewModel.currentIndex) {
            SendCryptoDetailsView(tx: tx, viewModel: viewModel).tag(1)
            SendCryptoQRScannerView(viewModel: viewModel).tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }
    
    var refreshButton: some View {
        Button {
            
        } label: {
            NavigationRefreshButton()
        }
    }
}

#Preview {
    SendCryptoView(tx: SendTransaction())
}
