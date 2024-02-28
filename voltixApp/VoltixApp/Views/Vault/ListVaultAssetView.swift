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
        ScrollView {
            LazyVStack {
                ForEach(appState.currentVault?.coins ?? [Coin](), id: \.self) { coin in
                    
                    VaultAssetsView(presentationStack: $presentationStack, tx: SendTransaction(toAddress: "", amount: "", memo: "", gas: "20", coin: coin))
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 5)
                }
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
                    let coin = vault.coins.first { $0.ticker == "USDC" }
                    if let coin {
                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
                            coin: coin,
                            toAddress: "0x6f2E21B6E20F3Ce7A1a8Ec132FD69CB6Fc603c3C",
                            toAmount: 100_000_000,
                            chainSpecific: BlockChainSpecific.ERC20(maxFeePerGasGwei: 42, priorityFeeGwei: 1, nonce: 1, gasLimit: 95000, contractAddr: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
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
