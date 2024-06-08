import SwiftUI

struct ChainDetailView: View {
    let group: GroupedChain
    let vault: Vault
    
    @State var showSheet = false
    @State var tokens: [Coin] = []
    @State var actions: [CoinAction] = []
    @StateObject var sendTx = SendTransaction()
    @State var isLoading = false

    @EnvironmentObject var viewModel: CoinSelectionViewModel

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
                        for coin in group.coins {
                            await viewModel.loadData(coin: coin)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                CustomTokenView(
                    showTokenSelectionSheet: $showSheet,
                    vault: vault,
                    group: group
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
