//
//  Keysign.swift
//  VoltixApp

import OSLog
import SwiftUI

struct KeysignView: View {
    let vault: Vault
    private let logger = Logger(subsystem: "keysign", category: "tss")

    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let keysignType: KeyType
    let messsageToSign: [String]
    let keysignPayload: KeysignPayload? // need to pass it along to the next view

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
                    KeyGenStatusText(status: NSLocalizedString("keysignFinished", comment: "KEYSIGN FINISHED..."))
                    VStack {
                        if let transactionHash = viewModel.etherScanService.transactionHash {
                            Text("Transaction Hash: \(transactionHash)")
                        } else if let errorMessage = viewModel.etherScanService.errorMessage {
                            Text("Error: \(errorMessage)")
                                .foregroundColor(.red)
                        }

                        if !viewModel.txid.isEmpty {
                            Text("Transaction Hash: \(viewModel.txid)")
                        }

                        Button(action: {
                            viewModel.isLinkActive = true
                        }) {
                            FilledButton(title: "DONE")
                        }
                    }
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
}

#Preview {
    KeysignView(
        vault: Vault.example,
        keysignCommittee: [],
        mediatorURL: "",
        sessionID: "session",
        keysignType: .ECDSA,
        messsageToSign: ["message"],
        keysignPayload: nil
    )
}
