//
//  Keysign.swift
//  VultisigApp

import OSLog
import SwiftUI

struct KeysignView: View {
    let vault: Vault
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let keysignType: KeyType
    let messsageToSign: [String]
    let keysignPayload: KeysignPayload? // need to pass it along to the next view
    let customMessagePayload: CustomMessagePayload?
    let transferViewModel: TransferViewModel?
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    let fastVaultPassword: String?
    @StateObject var viewModel = KeysignViewModel()

    @State var showAlert = false
    @State var showDoneText = false
    @State var showError = false

    @EnvironmentObject var globalStateViewModel: GlobalStateViewModel

    var body: some View {
        content
            .sensoryFeedback(.success, trigger: showDoneText)
            .sensoryFeedback(.error, trigger: showError)
            .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.status)
        #if os(iOS)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                viewModel.stopMessagePuller()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .navigationBarBackButtonHidden(viewModel.status == .KeysignFinished ? true : false)
        #else
            .onDisappear {
                viewModel.stopMessagePuller()
            }
        #endif

    }

    var content: some View {
        ZStack {
            switch viewModel.status {
            case .CreatingInstance:
                SendCryptoKeysignView()
            case .KeysignECDSA:
                SendCryptoKeysignView()
            case .KeysignEdDSA:
                SendCryptoKeysignView()
            case .KeysignFinished:
                keysignFinished
            case .KeysignFailed:
                sendCryptoKeysignView
            case .KeysignVaultMismatch:
                keysignVaultMismatchErrorView
            }

            PopupCapsule(text: "hashCopied", showPopup: $showAlert)
        }
        .onLoad {
            Task {
                await setData()
                await viewModel.startKeysign()
            }
        }
        .onChange(of: viewModel.txid) {
            movetoDoneView()
        }
    }

    var keysignFinished: some View {
        ZStack {
            if transferViewModel != nil, keysignPayload != nil {
                forStartKeysign
            } else {
                forJoinKeysign
            }
        }
        .onAppear {
            showDoneText = true
        }
    }

    var forStartKeysign: some View {
        Loader()
    }

    var forJoinKeysign: some View {
        JoinKeysignDoneView(vault: vault, viewModel: viewModel, showAlert: $showAlert)
            .onAppear {
                globalStateViewModel.showKeysignDoneView = true
            }
            .onDisappear {
                globalStateViewModel.showKeysignDoneView = false
            }
    }

    var sendCryptoKeysignView: some View {
        SendCryptoKeysignView(title: viewModel.keysignError, showError: true)
            .onAppear {
                showError = true
            }
    }

    var keysignVaultMismatchErrorView: some View {
        KeysignVaultMismatchErrorView()
            .onAppear {
                showError = true
            }
    }

    func setData() async {
        if let keysignPayload, keysignPayload.vaultPubKeyECDSA != vault.pubKeyECDSA {
            viewModel.status = .KeysignVaultMismatch
            return
        }

        await viewModel.setData(
            keysignCommittee: self.keysignCommittee,
            mediatorURL: self.mediatorURL,
            sessionID: self.sessionID,
            keysignType: self.keysignType,
            messagesToSign: self.messsageToSign,
            vault: self.vault,
            keysignPayload: keysignPayload,
            customMessagePayload: customMessagePayload,
            encryptionKeyHex: encryptionKeyHex,
            isInitiateDevice: self.isInitiateDevice,
            fastVaultPassword: self.fastVaultPassword
        )
    }

    private func movetoDoneView() {
        guard let transferViewModel = transferViewModel, !viewModel.txid.isEmpty else {
            return
        }

        transferViewModel.hash = viewModel.txid
        transferViewModel.approveHash = viewModel.approveTxid
        transferViewModel.moveToNextView()
    }
}

#Preview {
    ZStack {
        Background()

        KeysignView(
            vault: Vault.example,
            keysignCommittee: [],
            mediatorURL: "",
            sessionID: "session",
            keysignType: .ECDSA,
            messsageToSign: ["message"],
            keysignPayload: nil,
            customMessagePayload: nil,
            transferViewModel: nil,
            encryptionKeyHex: "",
            isInitiateDevice: false,
            fastVaultPassword: nil
        )
    }
    .environmentObject(HomeViewModel())
    .environmentObject(GlobalStateViewModel())
}
