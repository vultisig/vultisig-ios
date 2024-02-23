import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var unspentOutputsViewModel: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var tx: SendTransaction
    @StateObject var cryptoPriceViewModel = CryptoPriceService()
    @State private var signingTestView = false
    var body: some View {
        
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    
                    if let walletData = unspentOutputsViewModel.walletData {
                        if let cryptoPrices = cryptoPriceViewModel.cryptoPrices,
                           let bitcoinPriceUSD = cryptoPrices.prices["bitcoin"]?["usd"]
                        {
                            if let priceUsd = walletData.balanceInUSD(usdPrice: bitcoinPriceUSD) {
                                VaultItem(
                                    presentationStack: $presentationStack,
                                    coinName: tx.coin.chain.name,
                                    usdAmount: priceUsd,
                                    showAmount: false,
                                    address: walletData.address,
                                    isRadio: false,
                                    radioIcon: "",
                                    showButtons: true
                                ).padding()
                                AssetItem(
                                    coinName: tx.coin.ticker,
                                    amount: walletData.balanceInBTC,
                                    usdAmount: priceUsd,
                                    sendClick: {
                                        self.presentationStack.append(.sendInputDetails(tx))
                                    },
                                    swapClick: {}
                                )
                                .padding()
                            }
                        } else if let errorMessage = cryptoPriceViewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                        } else {
                            Text("Loading...")
                        }
                        
                    } else {
                        Text("Loading...")
                            .padding()
                    }
                    
                }
                .onAppear {
                    if let  vault = appState.currentVault {
                        let result = BitcoinHelper.getAddressFromPubKey(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                        switch result {
                            case .success(let addr):
                                print("bitcoin address is : \(addr)")
                            case .failure(let err):
                                print("fail to generate bitcoin address,error: \(err)")
                        }
                    }
                    
                    if unspentOutputsViewModel.walletData == nil {
                        Task {
                            await loadData()
                        }
                    }
                }
            }.refreshable {
                    // This block is called when a pull-to-refresh action is triggered by the user.
                Task {
                    await loadData()
                }
            }
            
                //            BottomBar(
                //                content: "CONTINUE",
                //                onClick: {
                //                    // Define the action for continue button
                //                }
                //            )
                //            .padding()
        }
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
            
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.refreshButton(action: {
                    Task {
                        await loadData()
                    }
                })
            }
        }
    }
    private func loadData() async {
        await unspentOutputsViewModel.fetchUnspentOutputs(for: tx.fromAddress)
        await cryptoPriceViewModel.fetchCryptoPrices(for: "bitcoin", for: "usd")
    }
}
