import Foundation
import SwiftUI

public struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @StateObject var sol: SolanaService = .shared
    @ObservedObject var tx: SendTransaction
    @State private var coinBalance: String = "0"
    @State private var balanceUSD: String = "0"
    @State private var isCollapsed = true
    @State private var isLoading = false
	
	@State private var ethAddressInfo: EthAddressInfo = EthAddressInfo()
	
    
    @StateObject var utxo = BlockchairService.shared
	@StateObject var eth = EtherScanService.shared
	
    class VaultAssetDebouncer {
        private var lastJob: DispatchWorkItem?
        private let queue: DispatchQueue
        private let delay: TimeInterval
        
        init(
            delay: TimeInterval,
            queue: DispatchQueue = DispatchQueue.main
        ) {
            self.delay = delay
            self.queue = queue
        }
        
        func debounce(
            action: @escaping () -> Void
        ) {
            lastJob?.cancel()
            let job = DispatchWorkItem(
                block: action
            )
            lastJob = job
            queue.asyncAfter(
                deadline: .now() + delay,
                execute: job
            )
        }
    }
    
    var debouncer = VaultAssetDebouncer(
        delay: 0.3
    )
    
    public var body: some View {
        VStack {
            contentView
        }
        .padding()
        .navigationTitle(
            appState.currentVault?.name ?? "Vault"
        )
        .modifier(
            InlineNavigationBarTitleModifier()
        )
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
            Image(
                systemName: isCollapsed ? "chevron.down" : "chevron.up"
            )
            .onTapGesture {
                withAnimation {
                    isCollapsed.toggle()
                }
            }
        }
        .frame(
            maxWidth: .infinity
        )
        .contentShape(
            Rectangle()
        )
        .padding(
            .vertical
        )
        
        if !isCollapsed {
            Divider()
            AssetItem(
                coinName: tx.coin.ticker,
                amount: coinBalance,
                usdAmount: balanceUSD,
                sendClick: {
                    print(
                        "Vault Assets View: \(tx.fromAddress)"
                    )
                    
                },
                swapClick: {
                }
            )
            .padding()
        }
    }
    
    private func loadData() {
        debouncer.debounce {
            isLoading = true
            Task {
                defer {
                    isLoading = false
                }
                
                let coinName = tx.coin.chain.name.lowercased()
                
                if tx.coin.chain.chainType == ChainType.UTXO {
                    await utxo.fetchBlockchairData(
                        for: tx.fromAddress,
                        coinName: coinName
                    )
                } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                   
					do{
						self.ethAddressInfo = try await eth.getEthInfo(
							for: tx.fromAddress
						)
					} catch {
						print("\(error.localizedDescription)")
					}
                } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                    
                } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
                    await sol.getSolanaBalance(
                        account: tx.fromAddress
                    )
                }
                
                await fetchCryptoPrices()
                updateState()
            }
        }
    }
    
    private func fetchCryptoPrices() async {
        await CryptoPriceService.shared.fetchCryptoPrices()
    }
    
    private func updateState() {
        DispatchQueue.main.async {
            self.balanceUSD = "US$ 0,00"
            self.coinBalance = "0.0"
            
            let coinName = tx.coin.chain.name.lowercased()
            let key: String = "\(tx.fromAddress)-\(coinName)"
            
            if tx.coin.chain.chainType == ChainType.UTXO {
                self.balanceUSD = utxo.blockchairData[key]?.address?.balanceInUSD ?? "US$ 0,00"
                self.coinBalance = utxo.blockchairData[key]?.address?.balanceInBTC ?? "0.0"
            } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
                
				tx.eth = self.ethAddressInfo
				if tx.coin.ticker.uppercased() == "ETH" {
					self.coinBalance = self.ethAddressInfo.ETH.balanceString ?? "0.0"
                    self.balanceUSD = self.ethAddressInfo.ETH.balanceInUsd ?? "US$ 0,00"
                } else if let tokenInfo = tx.token {
                    self.balanceUSD = tokenInfo.balanceInUsd
                    self.coinBalance = tokenInfo.balanceString
                }
				
            } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                
                
            } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
                if let priceRateUsd = CryptoPriceService.shared.cryptoPrices?.prices[Chain.Solana.name.lowercased()]?["usd"] {
                    self.balanceUSD = sol.solBalanceInUSD(
                        usdPrice: priceRateUsd
                    ) ?? "US$ 0,00"
                }
                self.coinBalance = sol.formattedSolBalance ?? "0.0"
            }
            
            self.isLoading = false
        }
    }
}

#Preview {
    VaultAssetsView(
        presentationStack: .constant([]),
        tx: SendTransaction()
    )
    .environmentObject(
        ApplicationState.shared
    )
}
