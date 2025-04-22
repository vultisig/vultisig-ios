import SwiftUI

struct TransactionMemoView: View {
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    let coin: Coin?
    
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var transactionMemoViewModel = TransactionMemoViewModel()
    @StateObject var transactionMemoVerifyViewModel = TransactionMemoVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
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
    
    var view: some View {
        VStack(spacing: 18) {
            ProgressBar(progress: transactionMemoViewModel.getProgress())
                .padding(.top, 12)

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
            transactionMemoViewModel: transactionMemoViewModel,
            vault: vault
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
                    customMessagePayload: nil,
                    transferViewModel: transactionMemoViewModel,
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
                    keysignView: $keysignView,
                    shareSheetViewModel: shareSheetViewModel
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
            if let hash = transactionMemoViewModel.hash, let chain = keysignPayload?.coin.chain  {
                SendCryptoDoneView(vault: vault, hash: hash, approveHash: nil, chain: chain, sendTransaction: tx, swapTransaction: nil)
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
        
        if let coin = coin {
            tx.coin = coin
        }
        
        await transactionMemoViewModel.loadGasInfoForSending(tx: tx)
        await transactionMemoViewModel.loadFastVault(tx: tx, vault: vault)
    }
}
