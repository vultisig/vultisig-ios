import SwiftUI

struct ChainDetailView: View {
    let group: GroupedChain
    let vault: Vault
    @ObservedObject var sendTx: SendTransaction
    
    @State var balanceInFiat: String?
    
    @State var showSheet = false
    @State var tokens: [Coin] = []
    @State var isLoading = false
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
                    Task{
                        await loadAllBalances()
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
            Task {
                await setData()
            }
        }
        .onChange(of: vault) {
            Task {
                await setData()
            }
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
            getCoinCell(coin)
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
    
    private func getCoinCell(_ coin: Coin) -> some View {
        VStack(spacing: 0) {
            Separator()
            if let viewModel = coinViewModels[coin.ticker] {
                NavigationLink {
                    CoinDetailView(coin: coin, group: group, vault: vault, viewModel: viewModel, sendTx: sendTx)
                } label: {
                    CoinCell(coin: coin, group: group, vault: vault, coinViewModel: viewModel)
                }
            }
        }
    }
    
    private func setData() async {
        viewModel.setData(for: vault)
        tokens = viewModel.groupedAssets[group.name] ?? []
        tokens.removeFirst()
        initializeViewModels()
        await loadAllBalances()
        
        if let coin = group.coins.first {
            sendTx.reset(coin: coin)
        }
    }
    
    private func loadAllBalances() async {
        isLoading = true
        for coin in group.coins {
            if let viewModel = coinViewModels[coin.ticker] {
                await viewModel.loadData(coin: coin)
            }
        }
        await calculateTotalBalanceInFiat()
        isLoading = false
    }
    
    private func initializeViewModels() {
        for coin in group.coins {
            if coinViewModels[coin.ticker] == nil {
                coinViewModels[coin.ticker] = CoinViewModel()
                Task{
                    await coinViewModels[coin.ticker]?.loadData(coin: coin)
                }
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
    ChainDetailView(group: GroupedChain.example, vault: Vault.example, sendTx: SendTransaction(), balanceInFiat: "$65,899")
        .environmentObject(TokenSelectionViewModel())
}
