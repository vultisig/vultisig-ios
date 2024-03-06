import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var uxto: UnspentOutputsService = UnspentOutputsService()
    @StateObject var eth: EthplorerAPIService = EthplorerAPIService()
    @StateObject var thor: ThorchainService = ThorchainService.shared
    @ObservedObject var tx: SendTransaction
    @State private var coinBalance: String = "0"
    @State private var balanceUSD: String = "0"
    @State private var isCollapsed = true
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).padding(2)
                    } else if let errorMessage = CryptoPriceService.shared.errorMessage {
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
                address: tx.coin.address,
                isRadio: false,
                radioIcon: "",
                showButtons: !isCollapsed,
                coin: tx.coin
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
            print("realoading data...")
            isLoading = true
            
            if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
                await uxto.fetchUnspentOutputs(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                await eth.getEthInfo(for: tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                await thor.fetchBalances(tx.fromAddress)
                await thor.fetchAccountNumber(tx.fromAddress)
            }
            
            await CryptoPriceService.shared.fetchCryptoPrices(for: "bitcoin,thorchain", for: "usd")
            
            DispatchQueue.main.async {
                updateState()
                isLoading = false
            }
        }
    }
    
    private func updateState() {
        
        self.balanceUSD = "US$ 0,00"
        self.coinBalance = "0.0"
        
        if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[tx.coin.chain.name.lowercased()]?["usd"] {
                self.balanceUSD = uxto.walletData?.balanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
            }
            self.coinBalance = uxto.walletData?.balanceInBTC ?? "0.0"
            
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            tx.eth = eth.addressInfo
            if tx.coin.ticker.uppercased() == "ETH" {
                self.coinBalance = eth.addressInfo?.ETH.balanceString ?? "0.0"
                self.balanceUSD = eth.addressInfo?.ETH.balanceInUsd ?? "US$ 0,00"
            } else if let tokenInfo = tx.token {
                self.balanceUSD = tokenInfo.balanceInUsd
                self.coinBalance = tokenInfo.balanceString
            }
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.THORChain.name.lowercased()]?["usd"] {
                self.balanceUSD = thor.runeBalanceInUSD(usdPrice: priceRateUsd) ?? "US$ 0,00"
            }
            self.coinBalance = thor.formattedRuneBalance ?? "0.0"
        }
    }
}
