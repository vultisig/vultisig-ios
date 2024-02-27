import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var uxto: UnspentOutputsService = UnspentOutputsService()
    @ObservedObject var tx: SendTransaction
    @StateObject var cryptoPrice = CryptoPriceService()
    @State private var coinBalance: String = "0"
    @State private var balanceUSD: String = "0"
    @State private var walletAddress: String = ""
    @State private var isCollapsed = true
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).padding(2)
                    } else if let errorMessage = cryptoPrice.errorMessage {
                        Text(errorMessage).foregroundColor(.red)
                    } else {
                        content
                    }
                }
                .onAppear {
                    loadData()
                }
            }
            .refreshable {
                loadData()
            }
        }
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .modifier(InlineNavigationBarTitleModifier())
    }
    
    @ViewBuilder
    private var content: some View {
        HStack {
            VaultItem(
                presentationStack: $presentationStack,
                coinName: tx.coin.chain.name,
                usdAmount: balanceUSD,
                showAmount: isCollapsed,
                address: walletAddress,
                isRadio: false,
                radioIcon: "",
                showButtons: !isCollapsed
            )
            Spacer()
            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                .padding(.leading)
                .animation(.easeInOut, value: isCollapsed)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.vertical)
        .onTapGesture {
            isCollapsed.toggle()
        }
        
        if !isCollapsed {
            Divider()
            AssetItem(
                coinName: tx.coin.ticker,
                amount: coinBalance,
                usdAmount: balanceUSD,
                sendClick: {
                    presentationStack.append(.sendInputDetails(tx))
                },
                swapClick: {}
            )
            .padding()
        }
    }
    
    private func loadData() {
        Task {
            isLoading = true
            await cryptoPrice.fetchCryptoPrices(for: tx.coin.chain.name.lowercased(), for: "usd")
            
            if tx.coin.chain.name.lowercased() == "bitcoin" {
                await uxto.fetchUnspentOutputs(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == "ethereum" {
                await fetchBalanceAndAddress(for: tx.coin)
            }
            
            DispatchQueue.main.async {
                updateState()
                isLoading = false
            }
        }
    }
    
    private func updateState() {
        if let priceRateUsd = cryptoPrice.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
            
            if tx.coin.chain.name.lowercased() == "bitcoin" {
                self.coinBalance = uxto.walletData?.balanceInBTC ?? "0"
                self.balanceUSD = uxto.walletData?.balanceInUSD(usdPrice: priceRateUsd) ?? "0"
                self.walletAddress = uxto.walletData?.address ?? ""
            } else if tx.coin.chain.name.lowercased() == "ethereum" {
                self.coinBalance = "0"
                self.balanceUSD = "US$ 0,00"
                self.walletAddress = "TO BE IMPLEMENTED"
            }
        }
    }
    
    private func fetchBalanceAndAddress(for coin: Coin) async {
            // Implement fetching balance and address for the given coin
    }
}
