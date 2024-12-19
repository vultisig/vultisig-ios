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
    @StateObject var viewModel = KeysignViewModel()
    
    @State var showAlert = false
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var globalStateViewModel: GlobalStateViewModel
    
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
            await setData()
            await viewModel.startKeysign()
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
    }
    
    var forStartKeysign: some View {
        Loader()
    }
    
    var forJoinKeysign: some View {
        JoinKeysignDoneView(vault: vault, viewModel: viewModel, showAlert: $showAlert)
            .onAppear {
                globalStateViewModel.hideBackForKeysign = true
            }
            .onDisappear {
                globalStateViewModel.hideBackForKeysign = false
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
            isInitiateDevice: self.isInitiateDevice
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
            isInitiateDevice: false
        )
    }
    .environmentObject(HomeViewModel())
    .environmentObject(GlobalStateViewModel())
}
