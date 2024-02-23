    //
    //  TestVaultAssetView.swift
    //  VoltixApp
    //

import SwiftUI

struct ListVaultAssetView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @State private var showingCoinList = false
    @StateObject var sendTransaction = SendTransaction()
    
    var body: some View {
        List {
            ForEach(appState.currentVault?.coins ?? [Coin](), id: \.self) {
                VaultAssetsView(presentationStack: $presentationStack, tx: SendTransaction(toAddress: "", amount: "", memo: "", gas: "20", coin: $0))
            }
        }
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCoinList) {
            AssetsList()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("add coins", systemImage: "plus") {
                    showingCoinList = true
                }
                NavigationButtons.refreshButton(action: {})
                Button("send", systemImage: "paperplane") {
                    self.presentationStack.append(.sendInputDetails(sendTransaction))
                }
                Button("join keysign",systemImage: "camera.viewfinder") {
                    self.presentationStack.append(.JoinKeysign)
                }
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
                print("hexPubKey: \(vault.pubKeyECDSA) - hexChainCode: \(vault.hexChainCode)")
                let result = BitcoinHelper.getBitcoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                switch result {
                    case .success(let btc):
                        self.sendTransaction.coin = btc
                    case .failure(let error):
                        print("error: \(error)")
                }
            }
        }
    }
}

#Preview {
    ListVaultAssetView(presentationStack: .constant([]))
}
