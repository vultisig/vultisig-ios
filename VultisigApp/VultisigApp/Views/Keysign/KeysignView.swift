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
    let transferViewModel: TransferViewModel?
    let encryptionKeyHex: String
    
    
    @StateObject var viewModel = KeysignViewModel()
    
    @State var showAlert = false
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            switch viewModel.status {
            case .CreatingInstance:
                SendCryptoKeysignView(title: "creatingTssInstance")
            case .KeysignECDSA:
                SendCryptoKeysignView(title: "signingWithECDSA")
            case .KeysignEdDSA:
                SendCryptoKeysignView(title: "signingWithEdDSA")
            case .KeysignFinished:
                keysignFinished
            case .KeysignFailed:
                SendCryptoKeysignView(title: "Sorry keysign failed, you can retry it,error: \(viewModel.keysignError)", showError: true)
            case .KeysignVaultMismatch:
                KeysignVaultMismatchErrorView()
            }
            
            PopupCapsule(text: "urlCopied", showPopup: $showAlert)
        }
        .task {
            await viewModel.startKeysign()
        }
        .onChange(of: viewModel.txid) {
            movetoDoneView()
        }
    }
    
    var keysignFinished: some View {
        ZStack {
            if transferViewModel != nil {
                forStartKeysign
            } else {
                forJoinKeysign
            }
        }
    }
    
    var forStartKeysign: some View {
        Loader()
    }
    
    var forJoinKeysign: some View {
        JoinKeysignDoneView(vault: vault, viewModel: viewModel, showAlert: $showAlert)
    }
    
    func setData() {
        guard let keysignPayload, keysignPayload.vaultPubKeyECDSA == vault.pubKeyECDSA else {
            viewModel.status = .KeysignVaultMismatch
            return
        }
        
        viewModel.setData(
            keysignCommittee: self.keysignCommittee,
            mediatorURL: self.mediatorURL,
            sessionID: self.sessionID,
            keysignType: self.keysignType,
            messagesToSign: self.messsageToSign,
            vault: self.vault,
            keysignPayload: keysignPayload,
            encryptionKeyHex: encryptionKeyHex
        )
    }
    
    private func movetoDoneView() {
        guard let transferViewModel = transferViewModel, !viewModel.txid.isEmpty else {
            return
        }
        
        transferViewModel.moveToNextView()
        transferViewModel.hash = viewModel.txid
        transferViewModel.approveHash = viewModel.approveTxid
    }
}

#Preview {
    KeysignView(
        vault: Vault.example,
        keysignCommittee: [],
        mediatorURL: "",
        sessionID: "session",
        keysignType: .ECDSA,
        messsageToSign: ["message"],
        keysignPayload: nil,
        transferViewModel: nil,
        encryptionKeyHex: "")
}
