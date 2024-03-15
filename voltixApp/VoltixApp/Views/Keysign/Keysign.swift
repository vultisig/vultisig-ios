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
        VStack {
            Spacer()
            switch viewModel.status {
                case .CreatingInstance:
                    KeyGenStatusText(status: NSLocalizedString("creatingTssInstance", comment: "CREATING TSS INSTANCE..."))
                case .KeysignECDSA:
                    KeyGenStatusText(status: NSLocalizedString("signingWithECDSA", comment: "SIGNING USING ECDSA KEY... "))
                case .KeysignEdDSA:
                    KeyGenStatusText(status: NSLocalizedString("signingWithEdDSA", comment: "SIGNING USING EdDSA KEY... "))
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
                    Text("Sorry keysign failed, you can retry it,error:\(viewModel.keysignError)")
            }
            Spacer()
        }
        .navigationDestination(isPresented: $viewModel.isLinkActive) {
            HomeView()
        }
        .onAppear {
            viewModel.setData(keysignCommittee: self.keysignCommittee,
                              mediatorURL: self.mediatorURL,
                              sessionID: self.sessionID,
                              keysignType: self.keysignType,
                              messagesToSign: self.messsageToSign,
                              vault: self.vault,
                              keysignPayload: self.keysignPayload)
        }
        .task {
            await viewModel.startKeysign()
        }
    }
}

#Preview {
    KeysignView(vault: Vault.example,
                keysignCommittee: [],
                mediatorURL: "",
                sessionID: "session",
                keysignType: .ECDSA,
                messsageToSign: ["message"],
                keysignPayload: nil)
}
