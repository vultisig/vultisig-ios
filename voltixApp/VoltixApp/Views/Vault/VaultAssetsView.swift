import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @ObservedObject var unspentOutputsViewModel: UnspentOutputsViewModel = UnspentOutputsViewModel()
    @ObservedObject var transactionDetailsViewModel: TransactionDetailsViewModel
    @StateObject var cryptoPriceViewModel = CryptoPriceViewModel()
    @State private var signingTestView = false
    var body: some View {
        
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    
                    if let walletData = unspentOutputsViewModel.walletData {
                        if let cryptoPrices = cryptoPriceViewModel.cryptoPrices,
                           let bitcoinPriceUSD = cryptoPrices.prices["bitcoin"]?["usd"] {
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
                                        self.presentationStack.append(.sendInputDetails(TransactionDetailsViewModel()))
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
                            await unspentOutputsViewModel.fetchUnspentOutputs(for: transactionDetailsViewModel.fromAddress)
                            await cryptoPriceViewModel.fetchCryptoPrices(for: "bitcoin", for: "usd")
                        }
                    }
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
                NavigationButtons.questionMarkButton
            }
        }
        .background(Color.white)
    }
}
