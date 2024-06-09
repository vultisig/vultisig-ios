import SwiftUI

struct ChainDetailView: View {
    let group: GroupedChain
    let vault: Vault
    
    @State var tokens: [Coin] = []
    @State var actions: [CoinAction] = []
    @StateObject var sendTx = SendTransaction()
    @State var isLoading = false
    @State var sheetType: SheetType? = nil
    
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    enum SheetType: Identifiable {
        case tokenSelection
        case customToken
        
        var id: Int {
            switch self {
            case .tokenSelection:
                return 1
            case .customToken:
                return 2
            }
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
                            await viewModel.loadData(coin: coin)
                        }
                        isLoading = false
                    }
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
        .onChange(of: vault) { _ in
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
                    addCustomTokenButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
        }
    }
    
    var actionButtons: some View {
        ChainDetailActionButtons(
            group: group,
            vault: vault,
            sendTx: sendTx
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
        ForEach(group.coins, id: \.self) { coin in
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
    
    var addCustomTokenButton: some View {
        Button {
            sheetType = .customToken
        } label: {
            chooseTokensButton(NSLocalizedString("customToken", comment: "Custom Token"))
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
}

#Preview {
    ChainDetailView(group: GroupedChain.example, vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
}
