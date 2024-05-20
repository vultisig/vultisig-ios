import SwiftUI

struct ChainDetailView: View {
    let group: GroupedChain
    let vault: Vault
    @State var balanceInFiat: String?
    
    @State var showSheet = false
    @State var tokens: [Coin] = []
    @State var actions: [CoinAction] = []
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
            Task {
                await setData()
                initializeViewModels()
            }
        }
        .onChange(of: vault) {
            Task {
                await setData()
                initializeViewModels()
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
        HStack(spacing: 12) {
            ForEach(actions, id: \.rawValue) { action in
                switch action {
                case .send:
                    sendButton
                case .swap:
                    swapButton
                case .memo:
                    memoButton
                case .deposit, .bridge:
                    ActionButton(title: action.title, fontColor: action.color)
                }
            }
        }
        .frame(height: 28)
    }

    var memoButton: some View {
        NavigationLink {
            TransactionMemoView(
                tx: sendTx,
                group: group,
                vault: vault
            )
        } label: {
            ActionButton(title: "Memos", fontColor: .turquoise600)
        }
    }
        
    var sendButton: some View {
        NavigationLink {
            SendCryptoView(
                tx: sendTx,
                group: group,
                vault: vault
            )
        } label: {
            ActionButton(title: "send", fontColor: .turquoise600)
        }
    }
    
    var swapButton: some View {
        NavigationLink {
            if let coin = group.coins.first {
                SwapCryptoView(coin: coin, coins: viewModel.allCoins, vault: vault)
            }
        } label: {
            ActionButton(title: "swap", fontColor: .persianBlue200)
        }
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
    
    private func setData() async {
        viewModel.setData(for: vault)
        tokens = viewModel.groupedAssets[group.name] ?? []
        tokens.removeFirst()
        
        actions = await viewModel.actionResolver.resolveActions(for: group.chain)
        
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
