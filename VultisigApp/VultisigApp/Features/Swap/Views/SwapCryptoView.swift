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
                        isInitiateDevice: input.isInitiateDevice
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

#if os(iOS)
import SwiftUI

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onLoad {
            UIApplication.shared.isIdleTimerDisabled = true
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
        .navigationTitle(NSLocalizedString(swapViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .toolbar {
            if showBackButton {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
            }

            if swapViewModel.currentIndex==3 {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    NavigationQRShareButton(
                        vault: vault,
                        type: .Keysign,
                        viewModel: shareSheetViewModel
                    )
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    var main: some View {
        views
    }

    var views: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onLoad {
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
    }

    var main: some View {
        VStack {
            headerMac
            views
        }
    }

    var headerMac: some View {
        SwapCryptoHeader(
            vault: vault,
            swapViewModel: swapViewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }

    var views: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
    }
}
#endif
