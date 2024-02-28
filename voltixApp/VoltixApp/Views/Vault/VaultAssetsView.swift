import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var uxto: UnspentOutputsService = UnspentOutputsService()
    @StateObject var eth: EthplorerAPIService = EthplorerAPIService()
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
                    self.walletAddress = tx.coin.address
                }
            }
            .refreshable {
                loadData()
            }
        }
        .padding()
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .modifier(InlineNavigationBarTitleModifier())
    }
    
    @ViewBuilder
    private var content: some View {
        HStack {
            VaultItem(
                presentationStack: $presentationStack,
                coinName: tx.coin.ticker,
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
                    print("Vault Assets View: \(tx.fromAddress)")
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
                await eth.getEthInfo(for: tx.fromAddress)
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
                
                // We need to pass it to the next view
                tx.eth = eth.addressInfo
                
                self.walletAddress = eth.addressInfo?.address ?? ""
                
                if tx.coin.ticker.uppercased() == "ETH" {
                    self.coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0" // "\(eth.addressInfo?.ETH.balance ?? 0.0)"
                    self.balanceUSD = eth.addressInfo?.ETH.balanceInUsd ?? ""
                } else {
                    if let tokenInfo = eth.addressInfo?.tokens.first(where: {$0.tokenInfo.symbol == "USDC"}) {
                        self.balanceUSD = tokenInfo.balanceInUsd
                        self.coinBalance = tokenInfo.balanceString
                    }
                }
            }
        }
    }
    
    
}
