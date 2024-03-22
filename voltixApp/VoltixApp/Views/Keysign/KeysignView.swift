//
//  Keysign.swift
//  VoltixApp

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
    let sendCryptoViewModel: SendCryptoViewModel?
    
    let logger = Logger(subsystem: "keysign", category: "tss")

    @StateObject var viewModel = KeysignViewModel()

    var body: some View {
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
            }
        }
        .onAppear {
            setData()
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
            if sendCryptoViewModel != nil {
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
        VStack {
            if !viewModel.txid.isEmpty {
                Text("Transaction Hash: \(viewModel.txid)")
            }

            Button(action: {
                viewModel.isLinkActive = true
            }) {
                FilledButton(title: "DONE")
            }
        }
    }
    
    private func setData() {
        viewModel.setData(
            keysignCommittee: self.keysignCommittee,
            mediatorURL: self.mediatorURL,
            sessionID: self.sessionID,
            keysignType: self.keysignType,
            messagesToSign: self.messsageToSign,
            vault: self.vault,
            keysignPayload: self.keysignPayload
        )
    }
    
    private func movetoDoneView() {
        guard let sendCryptoViewModel = sendCryptoViewModel, !viewModel.txid.isEmpty else {
            return
        }
        
        sendCryptoViewModel.moveToNextView()
        sendCryptoViewModel.hash = viewModel.txid
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
        sendCryptoViewModel: nil
    )
}
