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
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showingCoinList) {
            AssetsList()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                
                Button("join keysign",systemImage: "signature") {
                    self.presentationStack.append(.JoinKeysign)
                }.buttonStyle(PlainButtonStyle())
                Button("add coins", systemImage: "plus.square.on.square") {
                    showingCoinList = true
                }.buttonStyle(PlainButtonStyle())
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
                if vault.coins.isEmpty {
                    let bitcoinHelper = try? CoinFactory.createCoinHelper(for: Chain.Bitcoin.ticker)
                    
                    let result = bitcoinHelper?.getCoinDetails(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                    switch result {
                        case .success(let btc):
                            self.sendTransaction.coin = btc
                            vault.coins.append(btc)
                        case .failure(let error):
                            print("error: \(error)")
                        default:
                            print("ERROR")
                    }
                }
            }
        }
        
    }
}

#Preview {
    ListVaultAssetView(presentationStack: .constant([]))
}
