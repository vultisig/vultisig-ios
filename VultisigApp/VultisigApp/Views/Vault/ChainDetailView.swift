import SwiftUI

struct ChainDetailView: View {
    let group: GroupedChain
    let vault: Vault
    @State var balanceInFiat: String?
    
    @State var showSheet = false
    @State var tokens: [Coin] = []
    @State var isLoading = false
    @StateObject var sendTx = SendTransaction()
    @State var coinViewModels: [String: CoinViewModel] = [:]
    
    @EnvironmentObject var viewModel: TokenSelectionViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if isLoading {
                loader
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(group.name, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton() {
                    Task {
                        isLoading = true
                        
                        for coin in group.coins {
                            if let viewModel = coinViewModels[coin.ticker] {
                                await viewModel.loadData(coin: coin)
                            }
                        }
                        
                        await calculateTotalBalanceInFiat()
                        isLoading = false
                    }
                }
            }
        }
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                TokenSelectionView(
                    showTokenSelectionSheet: $showSheet,
                    vault: vault,
                    group: group,
                    tokens: tokens
                )
            }
        })
        .onAppear {
            setData()
            initializeViewModels()
        }
        .onChange(of: vault) {
            setData()
            initializeViewModels()
        }
    }
    
    var loader: some View {
        Loader()
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actionButtons
                content
                
                if tokens.count > 0 {
                    addButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
        }
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(group: group, vault: vault, sendTx: sendTx)
    }
    
    var content: some View {
        VStack(spacing: 0) {
            header
            cells
        }
        .cornerRadius(10)
    }
    
    var header: some View {
        ChainHeaderCell(group: group, balanceInFiat: balanceInFiat)
    }
    
    var cells: some View {
        ForEach(group.coins, id: \.self) { coin in
            VStack(spacing: 0) {
                Separator()
                if let viewModel = coinViewModels[coin.ticker] {
                    CoinCell(coin: coin, group: group, vault: vault, coinViewModel: viewModel)
                }
            }
        }
    }
    
    var addButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            chooseTokensButton
        }
    }
    
    var chooseTokensButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
            Spacer()
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
    
    private func setData() {
        viewModel.setData(for: vault)
        tokens = viewModel.groupedAssets[group.name] ?? []
        tokens.removeFirst()
        
        if let coin = group.coins.first {
            sendTx.reset(coin: coin)
        }
    }
    
    private func initializeViewModels() {
        for coin in group.coins {
            if coinViewModels[coin.ticker] == nil {
                coinViewModels[coin.ticker] = CoinViewModel()
            }
        }
    }
    
    private func calculateTotalBalanceInFiat() async {
        var totalBalance: Decimal = 0.0
        for coin in group.coins {
            if let viewModel = coinViewModels[coin.ticker],
               let balanceFiat = viewModel.balanceFiat?.fiatToDecimal()
            {
                totalBalance += balanceFiat
            }
        }
        balanceInFiat = totalBalance.formatToFiat(includeCurrencySymbol: true)
    }
}

#Preview {
    ChainDetailView(group: GroupedChain.example, vault: Vault.example, balanceInFiat: "$65,899")
        .environmentObject(TokenSelectionViewModel())
}
