import SwiftUI

struct FunctionCallView: View {
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    let coin: Coin?
    
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @StateObject var functionCallVerifyViewModel = FunctionCallVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
            .onLoad {
                Task {
                    await setData()
                    await loadGasInfo()
                }
            }
            .onChange(of: tx.coin) {
                Task {
                    await loadGasInfo()
                }
            }
            .onDisappear {
                functionCallViewModel.stopMediator()
            }
    }
    
    var view: some View {
        VStack(spacing: 18) {
            tabView
        }
        .blur(radius: functionCallViewModel.isLoading ? 1 : 0)
    }
    
    var tabView: some View {
        ZStack {
            switch functionCallViewModel.currentIndex {
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
        FunctionCallDetailsView(
            tx: tx,
            functionCallViewModel: functionCallViewModel,
            vault: vault,
            defaultCoin: coin
        )
    }
    
    var verifyView: some View {
        FunctionCallVerifyView(
            keysignPayload: $keysignPayload,
            depositViewModel: functionCallViewModel,
            depositVerifyViewModel: functionCallVerifyViewModel,
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
                    transferViewModel: functionCallViewModel,
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
                SendCryptoSigningErrorView(errorString: functionCallViewModel.errorMessage)
            }
        }
    }
    
    var doneView: some View {
        ZStack {
            if let hash = functionCallViewModel.hash, let chain = keysignPayload?.coin.chain  {
                SendCryptoDoneView(vault: vault, hash: hash, approveHash: nil, chain: chain, sendTransaction: tx, swapTransaction: nil)
            } else {
                SendCryptoSigningErrorView(errorString: functionCallViewModel.errorMessage)
            }
        }.onAppear() {
            Task{
                try await Task.sleep(for: .seconds(5)) // Back off 5s
                self.functionCallViewModel.stopMediator()
            }
        }
    }
    
    var errorView: some View {
        SendCryptoSigningErrorView(errorString: functionCallViewModel.errorMessage)
    }
    
    var loader: some View {
        Loader()
    }
    
    private func setData() async {
        if let coin = coin {
            tx.coin = coin
        }
    }
    
    private func loadGasInfo() async {
        await functionCallViewModel.loadGasInfoForSending(tx: tx)
        await functionCallViewModel.loadFastVault(tx: tx, vault: vault)
    }
}
