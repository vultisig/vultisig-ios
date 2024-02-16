import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var unspentOutputsViewModel: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var transactionDetailsViewModel: TransactionDetailsViewModel
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
                                    coinName: "Bitcoin",
                                    usdAmount: priceUsd,
                                    showAmount: false,
                                    address: walletData.address,
                                    isRadio: false,
                                    showButtons: true,
                                    onClick: {}
                                ).padding()
                                AssetItem(
                                    coinName: "BTC",
                                    amount: walletData.balanceInBTC,
                                    usdAmount: priceUsd,
                                    sendClick: {
                                        self.presentationStack.append(.sendInputDetails(transactionDetailsViewModel))
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
            
            BottomBar(
                content: "CONTINUE",
                onClick: {
                    // Define the action for continue button
                }
            )
            .padding()
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("VAULT")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.refreshButton(action: {
                    Task {
                        await loadData()
                    }
                })
            }
        }
        .background(Color.white)
    }
    private func loadData() async {
        transactionDetailsViewModel.fromAddress = appState.currentVault?.legacyBitcoinAddress ?? ""
        if !transactionDetailsViewModel.fromAddress.isEmpty {
            await unspentOutputsViewModel.fetchUnspentOutputs(for: transactionDetailsViewModel.fromAddress)
            await cryptoPriceViewModel.fetchCryptoPrices(for: "bitcoin", for: "usd")
        }
    }
}
