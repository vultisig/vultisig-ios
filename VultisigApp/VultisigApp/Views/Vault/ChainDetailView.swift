import SwiftUI

struct ChainDetailView: View {
    @ObservedObject var group: GroupedChain
    
    let vault: Vault

    var tokens: [Coin] {
        return vault.coins
            .filter { $0.chain == group.chain }
            .sorted()
    }

    @State var actions: [CoinAction] = []
    @StateObject var sendTx = SendTransaction()
    @State var isLoading = false
    @State var sheetType: SheetType? = nil

    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    @State var isWeweLinkActive = false

    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    enum SheetType: Int, Identifiable {
        case tokenSelection = 1
        case customToken = 2
        
        var id: Int {
            return self.rawValue
        }
    }
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if isLoading {
                Loader()
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(group.name, comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationRefreshButton() {
                    refreshAction()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            weweButton()
        }
        .navigationDestination(isPresented: $isSendLinkActive) {
            SendCryptoView(
                tx: sendTx,
                vault: vault
            )
        }
        .navigationDestination(isPresented: $isSwapLinkActive) {
            if let fromCoin = tokens.first {
                SwapCryptoView(fromCoin: fromCoin, vault: vault)
            }
        }
        .navigationDestination(isPresented: $isWeweLinkActive) {
            if let base = vault.coin(for: TokensStore.Token.baseEth), let wewe = vault.coin(for: TokensStore.Token.baseWewe) {
                SwapCryptoView(fromCoin: base, toCoin: wewe, vault: vault)
            }
        }
        .navigationDestination(isPresented: $isMemoLinkActive) {
            TransactionMemoView(
                tx: sendTx,
                vault: vault
            )
        }
        .refreshable {
            refreshAction()
        }
        .sheet(isPresented: Binding<Bool>(
            get: { sheetType != nil },
            set: { newValue in
                if !newValue {
                    sheetType = nil
                }
            }
        )) {
            if let sheetType = sheetType {
                switch sheetType {
                case .tokenSelection:
                    NavigationView {
                        TokenSelectionView(
                            chainDetailView: self,
                            vault: vault,
                            group: group
                        )
                    }
                case .customToken:
                    NavigationView {
                        CustomTokenView(
                            chainDetailView: self,
                            vault: vault,
                            group: group
                        )
                    }
                }
            }
        }
        .onAppear {
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
                
                if viewModel.hasTokens(chain: group.chain) {
                    addButton
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .background(Color.backgroundBlue)
            .colorScheme(.dark)
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
#if os(macOS)
            .padding(24)
#endif
        }
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(
            group: group,
            sendTx: sendTx,
            isSendLinkActive: $isSendLinkActive,
            isSwapLinkActive: $isSwapLinkActive,
            isMemoLinkActive: $isMemoLinkActive
        )
    }
    
    var content: some View {
        VStack(spacing: 0) {
            header
            cells
        }
        .cornerRadius(10)
    }
    
    var header: some View {
        ChainHeaderCell(group: group, isLoading: $isLoading)
    }
    
    var cells: some View {
        ForEach(tokens, id: \.id) { coin in
            getCoinCell(coin)
        }
    }
    
    var addButton: some View {
#if os(iOS)
        Button {
            sheetType = .tokenSelection
        } label: {
            chooseTokensButton(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        }
#elseif os(macOS)
        NavigationLink {
            sheetView
                .onAppear {
                    sheetType = .tokenSelection
                }
        } label: {
            chooseTokensButton(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
        }
#endif
    }
    
    var sheetView: some View {
        ZStack {
            if let sheetType = sheetType {
                switch sheetType {
                case .tokenSelection:
                    TokenSelectionView(
                        chainDetailView: self,
                        vault: vault,
                        group: group
                    )
                case .customToken:
                    CustomTokenView(
                        chainDetailView: self,
                        vault: vault,
                        group: group
                    )
                }
            }
        }
    }
    
    func chooseTokensButton(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(text)
            Spacer()
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }

    private func weweButton() -> some View {
        Button {
            viewModel.selectWeweIfNeeded(vault: vault)
            isWeweLinkActive = true
        } label: {
            FilledLabelButton {
                HStack(spacing: 10) {
                    Image("BuyWewe")
                    Text("BUY $WEWE")
                        .foregroundColor(.blue600)
#if os(iOS)
                        .font(.body16MontserratBold)
#elseif os(macOS)
                        .font(.body14MontserratBold)
#endif
                }
                .frame(height: 44)
            }
        }
        .padding(20)
    }

    private func getCoinCell(_ coin: Coin) -> some View {
        VStack(spacing: 0) {
            Separator()
            NavigationLink {
                CoinDetailView(coin: coin, group: group, vault: vault, sendTx: sendTx)
            } label: {
                CoinCell(coin: coin, group: group, vault: vault)
            }
        }
    }
    
    private func setData() async {
        isLoading = false
        viewModel.setData(for: vault)
        
        if let coin = group.coins.first {
            sendTx.reset(coin: coin)
        }
    }
    
    private func refreshAction(){
        Task {
            isLoading = true
            for coin in group.coins {
                await viewModel.loadData(coin: coin)
            }
            isLoading = false
        }
    }
}

#Preview {
    ChainDetailView(group: GroupedChain.example, vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
}
