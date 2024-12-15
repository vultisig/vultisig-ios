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
    @State var showAlert = false
    @State var resetActive = false

    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    enum SheetType: Int, Identifiable {
        case tokenSelection = 1
        case customToken = 2
        
        var id: Int {
            return self.rawValue
        }
    }
    
    var body: some View {
        content
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
                    await updateBalances()
                    await setData()
                }
                resetActive = true
            }
            .onDisappear {
                resetActive = false
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
    
    var views: some View {
        VStack(spacing: 0) {
            header
            cells
        }
        .cornerRadius(10)
    }
    
    var header: some View {
        ChainHeaderCell(
            vault: vault,
            group: group,
            isLoading: $isLoading,
            showAlert: $showAlert
        )
    }
    
    var cells: some View {
        ForEach(tokens, id: \.id) { coin in
            getCoinCell(coin)
        }
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
        .padding(.bottom, 32)
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
        
        guard resetActive else {
            return
        }
        
        if let coin = group.coins.first {
            sendTx.reset(coin: coin)
        }
    }

    private func updateBalances() async {
        for coin in group.coins {
            await viewModel.loadData(coin: coin)
        }
    }

    func refreshAction(){
        Task {
            isLoading = true

            await updateBalances()

            for coin in group.coins where coin.isNativeToken {
                await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
            }
            isLoading = false
        }
    }
}

#Preview {
    ChainDetailView(group: GroupedChain.example, vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
}
