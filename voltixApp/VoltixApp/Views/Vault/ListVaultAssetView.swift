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
                Button("join keysign", systemImage: "signature") {
                    self.presentationStack.append(.JoinKeysign)
                }.buttonStyle(PlainButtonStyle())
                Button("add coins", systemImage: "plus.square.on.square") {
                    showingCoinList = true
                }.buttonStyle(PlainButtonStyle())

                Button("test", systemImage: "doc.questionmark") {
                    guard let vault = appState.currentVault else { return }
                    let coin = vault.coins.first { $0.ticker == "ETH" }
                    if let coin {
                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
                            coin: coin,
                            toAddress: "0x6f2E21B6E20F3Ce7A1a8Ec132FD69CB6Fc603c3C",
                            toAmount: 100_000_000, // in Gwei
                            chainSpecific: BlockChainSpecific.Ethereum(maxFeePerGasGwei: 24, priorityFeeGwei: 1, nonce: 0, gasLimit: 21_000),
                            utxos: [],
                            memo: nil)))
                    }
                }.buttonStyle(PlainButtonStyle())
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
                print("hexPubKey: \(vault.pubKeyECDSA) - hexChainCode: \(vault.hexChainCode)")
                let result = BitcoinHelper.getBitcoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                switch result {
                    case .success(let btc):
                        self.sendTransaction.coin = btc

                        // SET BTC as default if none
                        if vault.coins.count == 0 {
                            vault.coins.append(btc)
                        }

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
