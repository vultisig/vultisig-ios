//
//  TestVaultAssetView.swift
//  VoltixApp
//

import SwiftUI
import WalletCore

struct ListVaultAssetView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @State private var showingCoinList = false
    @StateObject var sendTransaction = SendTransaction()
    @Environment(\.colorScheme) var colorScheme
    
    private var listItemBackgroundColor: Color {
        switch colorScheme {
            case .light:
                // Apply a light mode-specific color
                // return Color(UIColor.systemGroupedBackground)
                return Color.systemFill
            case .dark:
                // Apply the dark mode color
                return Color.secondarySystemGroupedBackground
            @unknown default:
                // Fallback color
                return Color.systemBackground
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(appState.currentVault?.coins ?? [Coin](), id: \.self) { coin in
                    
                    VaultAssetsView(presentationStack: $presentationStack, tx: SendTransaction(toAddress: "", amount: "", memo: "", gas: "20", coin: coin))
                        // .background(Color(UIColor.secondarySystemGroupedBackground))
                        .background(self.listItemBackgroundColor)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .padding(.horizontal)
                        .padding(.top, 10)
                }
            }
        }
        .padding(.vertical)
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .sheet(isPresented: $showingCoinList) {
            AssetsList()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("join keysign", systemImage: "signature") {
                    self.presentationStack.append(.JoinKeysign)
                }.buttonStyle(PlainButtonStyle())
                Button("add coins", systemImage: "plus.square.on.square") {
                    showingCoinList = true
                }.buttonStyle(PlainButtonStyle())
                
                Button("test", systemImage: "doc.questionmark") {
                    guard let vault = appState.currentVault else { return }
                    // swap RUNE to USDT
                    let coin = vault.coins.first { $0.ticker == "BCH" }
                    if let coin {
                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
                            coin: coin,
                            toAddress: "qqgy8ndpz7uqw3lphgn3h23czhdlkquuwg7r568mvd",
                            toAmount: 1000000, //
                            chainSpecific: BlockChainSpecific.Bitcoin(byteFee: 10),
                            utxos: [
                                UtxoInfo(hash: "71787a90556de944fcea8d8ff7478e535092638a68491b60b5661dfd871c40e4", amount: 10000000, index: 0)
                            ],
                            memo: "",
                            swapPayload: nil)))
                    }
                }.buttonStyle(PlainButtonStyle())
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
                let result = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode).getCoin()
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
