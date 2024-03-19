//
//  SendCryptoView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct SendCryptoView: View {
    @ObservedObject var tx: SendTransaction
    let group: GroupedChain
    
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @StateObject var coinViewModel = CoinViewModel()
    @StateObject var utxoBtc = BitcoinUnspentOutputsService()
    @StateObject var utxoLtc = LitecoinUnspentOutputsService()
    @StateObject var eth = EthplorerAPIService()
    @StateObject var thor = ThorchainService.shared
    @StateObject var sol: SolanaService = SolanaService.shared
    
    @StateObject var cryptoPrice = CryptoPriceService.shared
    @StateObject var web3Service = Web3Service()
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(sendCryptoViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .onAppear {
            Task {
                await setData()
            }
        }
        .onChange(of: tx.coin) {
            Task {
                await setData()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: sendCryptoViewModel.getProgress())
                .padding(.top, 30)
            tabView
        }
    }
    
    var tabView: some View {
        TabView(selection: $sendCryptoViewModel.currentIndex) {
            detailsView.tag(1)
            SendCryptoQRScannerView(viewModel: sendCryptoViewModel).tag(2)
            SendCryptoPairView(viewModel: sendCryptoViewModel).tag(3)
            SendCryptoQRScannerView(viewModel: sendCryptoViewModel).tag(4)
            SendCryptoVerifyView(viewModel: sendCryptoViewModel).tag(5)
            SendCryptoKeysignView(viewModel: sendCryptoViewModel).tag(6)
            SendCryptoDoneView().tag(7)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }
    
    var detailsView: some View {
        SendCryptoDetailsView(
            tx: tx,
            utxoBtc: utxoBtc,
            utxoLtc: utxoLtc,
            eth: eth,
            thor: thor,
            sol: sol,
            sendCryptoViewModel: sendCryptoViewModel,
            coinViewModel: coinViewModel,
            group: group
        )
    }
    
    private func setData() async {
        await coinViewModel.loadData(
            utxoBtc: utxoBtc,
            utxoLtc: utxoLtc,
            eth: eth,
            thor: thor,
            tx: tx
        )
        sendCryptoViewModel.reloadTransactions(
            tx: tx,
            utxoBtc: utxoBtc,
            utxoLtc: utxoLtc,
            eth: eth,
            thor: thor,
            sol: sol,
            cryptoPrice: cryptoPrice,
            web3Service: web3Service
        )
    }
}

#Preview {
    SendCryptoView(tx: SendTransaction(), group: GroupedChain.example)
}
