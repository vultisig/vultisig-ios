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
                
//                Button("test", systemImage: "doc.questionmark") {
//                    guard let vault = appState.currentVault else { return }
//                    // swap RUNE to USDT
//                    let coin = vault.coins.first { $0.ticker == "RUNE" }
//                    if let coin {
//                        self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
//                            coin: coin,
//                            toAddress: "",
//                            toAmount: 1000000, // 0.01 RUNE
//                            chainSpecific: BlockChainSpecific.THORChain(accountNumber: 96761, sequence: 1),
//                            utxos: [],
//                            memo: "voltix",
//                            swapPayload: THORChainSwapPayload(fromAddress: coin.address,
//                                                              fromAsset: THORChainSwapAsset.with{
//                                                                  $0.chain = .thor
//                                                                  $0.symbol = "RUNE"
//                                                                  $0.tokenID = ""
//                                                              },
//                                                              toAsset: THORChainSwapAsset.with{
//                                                                  $0.chain = .eth
//                                                                  $0.symbol = "ETH"
//                                                                  $0.tokenID = ""
//                                                              },
//                                                              toAddress: "0xe5F238C95142be312852e864B830daADB9B7D290",
//                                                              vaultAddress: "0x4f2f271e58e94a8e888573c811e626e86b113167", // THIS one is very important , you need to get the latest from THORChain
//                                                              routerAddress: "0xD37BbE5744D730a1d98d8DC97c42F0Ca46aD7146",
//                                                              fromAmount: "1000000",
//                                                              toAmountLimit: "100"))))
//                    }
//                }.buttonStyle(PlainButtonStyle())
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
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
