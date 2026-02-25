//
//  SwapCryptoView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {
    let fromCoin: Coin?
    let toCoin: Coin?
    let vault: Vault

    @State var keysignView: KeysignView?

    @StateObject var tx = SwapTransaction()
    @StateObject var swapViewModel = SwapCryptoViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    init(fromCoin: Coin? = nil, toCoin: Coin? = nil, vault: Vault) {
        self.fromCoin = fromCoin
        self.toCoin = toCoin
        self.vault = vault
    }

    var body: some View {
        content
            .onLoad {
                if let fromCoin {
                    tx.fromCoin = fromCoin
                }
            }
    }

    var view: some View {
        VStack(spacing: 18) {
            tabView
        }
    }

    @ViewBuilder
    var tabView: some View {
        ZStack {
            switch swapViewModel.currentIndex {
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
    }

    var detailsView: some View {
        SwapCryptoDetailsView(tx: tx, swapViewModel: swapViewModel, vault: vault)
    }

    var verifyView: some View {
        SwapVerifyView(tx: tx, swapViewModel: swapViewModel, vault: vault)
    }

    var pairView: some View {
        ZStack {
            if let keysignPayload = swapViewModel.keysignPayload {
                KeysignDiscoveryView(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    customMessagePayload: nil,
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
                    shareSheetViewModel: shareSheetViewModel,
                    previewType: .Swap,
                    swapTransaction: tx
                ) { input in
                    self.keysignView = KeysignView(
                        vault: input.vault,
                        keysignCommittee: input.keysignCommittee,
                        mediatorURL: input.mediatorURL,
                        sessionID: input.sessionID,
                        keysignType: input.keysignType,
                        messsageToSign: input.messsageToSign,
                        keysignPayload: input.keysignPayload,
                        customMessagePayload: input.customMessagePayload,
                        transferViewModel: swapViewModel,
                        encryptionKeyHex: input.encryptionKeyHex,
                        isInitiateDevice: input.isInitiateDevice,
                        fastVaultPassword: input.fastVaultPassword
                    )
                    swapViewModel.moveToNextView()
                }
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
                SendCryptoSigningErrorView(errorString: swapViewModel.error?.localizedDescription ?? "Error")
            }
        }
    }

    var doneView: some View {
        ZStack {
            if let hash = swapViewModel.hash {
                SendCryptoDoneView(
                    vault: vault, hash: hash, approveHash: swapViewModel.approveHash,
                    chain: tx.fromCoin.chain,
                    progressLink: swapViewModel.progressLink(tx: tx, hash: hash),
                    sendTransaction: nil,
                    swapTransaction: tx,
                    isSend: false
                )
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            } else {
                SendCryptoSigningErrorView(errorString: swapViewModel.error?.localizedDescription ?? "Error")
            }
        }.onAppear {
            Task {
                try? await Task.sleep(for: .seconds(5))
                swapViewModel.stopMediator()
            }
        }
    }

    var errorView: some View {
        SendCryptoSigningErrorView(errorString: swapViewModel.error?.localizedDescription ?? "Error")
    }

    var showBackButton: Bool {
        swapViewModel.currentIndex != 1 && swapViewModel.currentIndex != 5
    }

    var backButton: some View {
        return Button {
            swapViewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
    }
}

#Preview {
    SwapCryptoView(vault: .example)
}
