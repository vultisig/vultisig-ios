import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var unspentOutputsViewModel: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var tx: SendTransaction
    @StateObject var cryptoPriceViewModel = CryptoPriceService()
    @State private var isCollapsed = true
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    if let walletData = unspentOutputsViewModel.walletData, let cryptoPrices = cryptoPriceViewModel.cryptoPrices, let bitcoinPriceUSD = cryptoPrices.prices["bitcoin"]?["usd"], let priceUsd = walletData.balanceInUSD(usdPrice: bitcoinPriceUSD) {
                        
                        HStack{
                            VaultItem(
                                presentationStack: $presentationStack,
                                coinName: tx.coin.chain.name,
                                usdAmount: priceUsd,
                                showAmount: isCollapsed,
                                address: walletData.address,
                                isRadio: false,
                                radioIcon: "",
                                showButtons: !isCollapsed
                            )
                            Spacer()
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .padding(.leading)
                                .animation(.easeInOut, value: isCollapsed)
                        }
                        .frame(maxWidth: .infinity) // Ensure the HStack fills the button horizontally
                        .contentShape(Rectangle()) // Makes the entire area within the frame tappable
                        .padding(.vertical)
                        .onTapGesture {
                            isCollapsed.toggle()
                        }
                        
                        if !isCollapsed {
                            Divider()
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
                        ProgressView().progressViewStyle(.circular).padding(2)
                    }
                }
                .onAppear {
                    if let vault = appState.currentVault {
                        let helper = try? CoinFactory.createCoinHelper(for: tx.coin.ticker)
                        let result = helper?.getAddressFromPublicKey(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                        switch result {
                            case .success(let addr):
                                print("the \(tx.coin.ticker) address is : \(addr)")
                            case .failure(let err):
                                print("fail to generate \(tx.coin.ticker) address,error: \(err)")
                            default:
                                print("Error")
                        }
                    }
                    
                    if unspentOutputsViewModel.walletData == nil {
                        Task {
                            await loadData()
                        }
                    }
                }
            }
            .refreshable {
                Task {
                    await loadData()
                }
            }
        }
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
            // ToolbarItem(placement: .navigationBarTrailing) {
            //     NavigationButtons.refreshButton(action: {
            //         Task {
            //             await loadData()
            //         }
            //     })
            // }
        }
    }
    
    private func loadData() async {
        await unspentOutputsViewModel.fetchUnspentOutputs(for: tx.fromAddress)
        await cryptoPriceViewModel.fetchCryptoPrices(for: "bitcoin", for: "usd")
    }
}
