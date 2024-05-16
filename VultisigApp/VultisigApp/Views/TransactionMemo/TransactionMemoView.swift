import SwiftUI

struct TransactionMemoView: View {
    @ObservedObject var tx: SendTransaction
    let group: GroupedChain
    let vault = ApplicationState.shared.currentVault ?? Vault(name: "default")
    
    @StateObject var transactionMemoViewModel = TransactionMemoViewModel()
    @StateObject var transactionMemoVerifyViewModel = TransactionMemoVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationTitle(NSLocalizedString(transactionMemoViewModel.currentTitle, comment: "SendCryptoView title"))
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(.keyboard)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleBackTap()
                    } label: {
                        NavigationBlankBackButton()
                    }
                }
            }
            .onAppear {
                Task {
                    await setData()
                }
            }
            .onChange(of: tx.coin) {
                Task {
                    await setData()
                }
            }
            .onDisappear(){
                transactionMemoViewModel.stopMediator()
            }
    }
    
    var content: some View {
        ZStack {
            Background()
            view
            
            if transactionMemoViewModel.isLoading || transactionMemoVerifyViewModel.isLoading {
                loader
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    var view: some View {
        VStack(spacing: 30) {
            ProgressBar(progress: transactionMemoViewModel.getProgress())
                .padding(.top, 30)
            tabView
        }
        .blur(radius: transactionMemoViewModel.isLoading ? 1 : 0)
    }
    
    var tabView: some View {
        ZStack {
            switch transactionMemoViewModel.currentIndex {
            case 1:
                detailsView
            case 2:
                verifyView
            case 3:
                pairView
            case 4:
                keysign
            case 5:
                doneView
            default:
                errorView
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    var detailsView: some View {
        TransactionMemoDetailsView(
            tx: tx,
            depositViewModel: transactionMemoViewModel,
            group: group
        )
    }
    
    var verifyView: some View {
        TransactionMemoVerifyView(
            keysignPayload: $keysignPayload,
            depositViewModel: transactionMemoViewModel,
            depositVerifyViewModel: transactionMemoVerifyViewModel,
            tx: tx,
            vault: vault
        )
    }
    
    var pairView: some View {
        ZStack {
            if let keysignPayload = keysignPayload {
                KeysignDiscoveryView(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    transferViewModel: transactionMemoViewModel,
                    keysignView: $keysignView
                )
            } else {
                SendCryptoVaultErrorView()
            }
        }
    }
    
    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                SendCryptoSigningErrorView()
            }
        }
    }
    
    var doneView: some View {
        ZStack {
            if let hash = transactionMemoViewModel.hash {
                SendCryptoDoneView(vault:vault,hash: hash,explorerLink: Endpoint.getExplorerURL(chainTicker: keysignPayload?.coin.chain.ticker ?? "", txid: hash))
            } else {
                SendCryptoSigningErrorView()
            }
        }.onAppear() {
            Task{
                try await Task.sleep(for: .seconds(5)) // Back off 5s
                self.transactionMemoViewModel.stopMediator()
            }
        }
    }
    
    var errorView: some View {
        SendCryptoSigningErrorView()
    }
    
    var loader: some View {
        Loader()
    }
    
    private func setData() async {
        await transactionMemoViewModel.loadGasInfoForSending(tx: tx)
    }
    
    private func handleBackTap() {
        guard transactionMemoViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        transactionMemoViewModel.handleBackTap()
    }
}

#Preview {
    TransactionMemoView(
        tx: SendTransaction(),
        group: GroupedChain.example
    )
}
