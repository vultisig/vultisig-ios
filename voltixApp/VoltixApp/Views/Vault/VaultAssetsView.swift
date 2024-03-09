import SwiftUI
import Foundation




public struct VaultAssetsView: View {
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
    
        // I had to create a debouncer since we are fetching data from network and or the cache
        // The view was getting crazy.
    class VaultAssetDebouncer {
        private var lastJob: DispatchWorkItem?
        private let queue: DispatchQueue
        private let delay: TimeInterval
        
        init(delay: TimeInterval, queue: DispatchQueue = DispatchQueue.main) {
            self.delay = delay
            self.queue = queue
        }
        
        func debounce(action: @escaping () -> Void) {
            lastJob?.cancel()
            let job = DispatchWorkItem(block: action)
            lastJob = job
            queue.asyncAfter(deadline: .now() + delay, execute: job)
        }
    }
    
    var debouncer = VaultAssetDebouncer(delay: 0.3)
    
    
    public var body: some View {
        VStack {
            contentView
        }
        .padding()
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .modifier(InlineNavigationBarTitleModifier())
        .onAppear {
            loadData()
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
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
                .onTapGesture {
                    withAnimation {
                        isCollapsed.toggle()
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.vertical)
        
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
        debouncer.debounce {
            isLoading = true
            Task {
                defer { isLoading = false }
                
                do {
                    switch tx.coin.chain.name.lowercased() {
                        case Chain.Bitcoin.name.lowercased():
                            await uxto.fetchUnspentOutputs(for: tx.fromAddress)
                        case Chain.Ethereum.name.lowercased():
                            await eth.getEthInfo(for: tx.fromAddress)
                        case Chain.THORChain.name.lowercased():
                            await thor.fetchBalances(tx.fromAddress)
                            await thor.fetchAccountNumber(tx.fromAddress)
                        default:
                            break
                    }
                    
                    await fetchCryptoPrices()
                    
                    DispatchQueue.main.async {
                        updateState()
                    }
                } catch {
                    print("Error loading data: \(error)")
                }
            }
        }
    }
    
    private func fetchCryptoPrices() async {
        await CryptoPriceService.shared.fetchCryptoPrices(for: "bitcoin,thorchain", for: "usd")
    }
    
    private func updateState() {
        DispatchQueue.main.async {
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
            self.isLoading = false
        }
    }
}

