import SwiftUI

struct ChainDetailView: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    
    @State var tokens: [CoinMeta] = []
    @State var actions: [CoinAction] = []
    @StateObject var sendTx = SendTransaction()
    @State var isLoading = false
    @State var sheetType: SheetType? = nil
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
#if os(iOS)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
#endif
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
            vault: vault,
            sendTx: sendTx,
            coin: group.nativeCoin
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
        ForEach(group.coins.sorted(by: {
            $0.isNativeToken || ($0.balanceInFiatDecimal > $1.balanceInFiatDecimal)
        }), id: \.id) { coin in
            getCoinCell(coin)
        }
    }
    
    var addButton: some View {
        Button {
            sheetType = .tokenSelection
        } label: {
            chooseTokensButton(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
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
        tokens = viewModel.groupedAssets[group.name] ?? []
        tokens.removeFirst()
        
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
