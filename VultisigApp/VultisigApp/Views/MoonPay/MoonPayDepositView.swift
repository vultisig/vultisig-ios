import SwiftUI

struct MoonPayDepositView: View {
    let depositPayload: MoonPayDepositPayload
    let vault: Vault

    @StateObject var tx = SendTransaction()
    @StateObject var sendCryptoViewModel = SendCryptoViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil

    @Environment(\.dismiss) var dismiss

    var body: some View {
        content
            .onAppear {
                setupTransaction()
            }
    }

    var content: some View {
        ZStack {
            Background()
            view
        }
    }

    var view: some View {
        VStack(spacing: 18) {
            ProgressBar(progress: sendCryptoViewModel.getProgress())
                .padding(.top, 12)

            tabView
        }
    }

    var tabView: some View {
        ZStack {
            switch sendCryptoViewModel.currentIndex {
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
        SendCryptoDetailsView(
            tx: tx,
            sendCryptoViewModel: sendCryptoViewModel,
            vault: vault
        )
    }

    var verifyView: some View {
        SendCryptoVerifyView(
            keysignPayload: $keysignPayload,
            sendCryptoViewModel: sendCryptoViewModel,
            sendCryptoVerifyViewModel: SendCryptoVerifyViewModel(),
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
                    transferViewModel: sendCryptoViewModel,
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
                    keysignView: $keysignView,
                    shareSheetViewModel: shareSheetViewModel,
                    previewType: .Send
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
            if let hash = sendCryptoViewModel.hash, let chain = keysignPayload?.coin.chain {
                SendCryptoDoneView(
                    vault: vault,
                    hash: hash,
                    approveHash: nil,
                    chain: chain,
                    sendTransaction: tx,
                    swapTransaction: nil
                )
            } else {
                SendCryptoSigningErrorView()
            }
        }
    }

    var errorView: some View {
        SendCryptoSigningErrorView()
    }

    private func setupTransaction() {
        // Set up the transaction with the deposit payload details
        if let coin = vault.coins.first(where: { $0.chain.ticker == depositPayload.cryptoCurrencyCode }) {
            tx.coin = coin
            tx.toAddress = depositPayload.depositWalletAddress
            tx.amount = BigInt(depositPayload.cryptoCurrencyAmountSmallestDenomination)
        }
    }
}
