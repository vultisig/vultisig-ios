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
    @Environment(\.colorScheme) var colorScheme
    
    private var listItemBackgroundColor: Color {
        switch colorScheme {
            case .light:
                    // Apply a light mode-specific color
                // return Color(UIColor.systemGroupedBackground)
                return Color(UIColor.systemFill)
            case .dark:
                    // Apply the dark mode color
                return Color(UIColor.secondarySystemGroupedBackground)
            @unknown default:
                    // Fallback color
                return Color(UIColor.systemBackground)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(appState.currentVault?.coins ?? [Coin](), id: \.self) { coin in
                    
                    VaultAssetsView(presentationStack: $presentationStack, tx: SendTransaction(toAddress: "", amount: "", memo: "", gas: "20", coin: coin))
                        //.background(Color(UIColor.secondarySystemGroupedBackground))
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
                    let coin = vault.coins.first { $0.ticker == "SOL" }
                    if let coin {
                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
                            coin: coin,
                            toAddress: "thor1kerhp6n4hywg7jjphedds5qgyzrhg8murqtnnf",
                            toAmount: 100_000_0, // 0.01 RUNE
                            chainSpecific: BlockChainSpecific.Solana(recentBlockHash: "D9xgxNtjPfZMNDnQbywr4h3XNy67pN8KNJfKmHPwoqu9"),
                            utxos: [],
                            memo: "voltix")))
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
