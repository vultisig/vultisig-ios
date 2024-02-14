import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @ObservedObject var unspentOutputsViewModel: UnspentOutputsViewModel = UnspentOutputsViewModel()
    @ObservedObject var transactionDetailsViewModel: TransactionDetailsViewModel
    
    @State private var signingTestView = false
    var body: some View {
        
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    
                    if let walletData = unspentOutputsViewModel.walletData {
                        
                        VaultItem(
                            coinName: "Bitcoin",
                            amount: walletData.balanceInBTC,
                            showAmount: false,
                            coinAmount: walletData.balanceInBTC,
                            address: walletData.address,
                            isRadio: false,
                            showButtons: true,
                            onClick: {}
                        )
                        .padding()
                        
                        AssetItem(
                            coinName: "BTC",
                            amount: walletData.balanceInBTC,
                            usdAmount: walletData.balanceInBTC,
                            sendClick: {
                                self.presentationStack.append(.sendInputDetails(TransactionDetailsViewModel()))
                            },
                            swapClick: {}
                        )
                        .padding()
                    } else {
                        Text("Error to fetch the data")
                            .padding()
                    }
                    
                    
                }
                .onAppear {
                    if unspentOutputsViewModel.walletData == nil {
                        Task {
                            await unspentOutputsViewModel.fetchUnspentOutputs(for: transactionDetailsViewModel.fromAddress)
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
#if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationButtons.questionMarkButton
            }
#else
            ToolbarItem {
                NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem {
                NavigationButtons.questionMarkButton
            }
#endif
        }
        
        .background(Color.white)
    }
}
