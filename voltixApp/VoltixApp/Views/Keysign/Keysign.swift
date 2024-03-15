//
//  Keysign.swift
//  VoltixApp

import Dispatch
import Foundation
import Mediator
import OSLog
import SwiftUI
import Tss
import WalletCore

struct KeysignView: View {
    let vault: Vault
    private let logger = Logger(subsystem: "keysign", category: "tss")
    
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let keysignType: KeyType
    let messsageToSign: [String]
    let keysignPayload: KeysignPayload? // need to pass it along to the next view
    
    @State private var tssService: TssServiceImpl? = nil
    @State private var tssMessenger: TssMessengerImpl? = nil
    @State private var stateAccess: LocalStateAccessorImpl? = nil
    @State private var keysignError: String? = nil
    @State var signatures = [String: TssKeysignResponse]()
    @State private var messagePuller = MessagePuller()
    @State private var txid: String = ""
    @StateObject private var etherScanService = EtherScanService()
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
                        if let transactionHash = etherScanService.transactionHash {
                            Text("Transaction Hash: \(transactionHash)")
                        } else if let errorMessage = etherScanService.errorMessage {
                            Text("Error: \(errorMessage)")
                                .foregroundColor(.red)
                        }
						
                        if !txid.isEmpty {
                            Text("Transaction Hash: \(txid)")
                        }
						
                        Button(action: {
                            viewModel.isLinkActive = true
                        }) {
                            FilledButton(title: "DONE")
                        }	
                    }
                case .KeysignFailed:
                    Text("Sorry keysign failed, you can retry it,error:\(self.keysignError ?? "")")
                        .onAppear {
                            self.messagePuller.stop()
                        }
            }
            Spacer()
        }
        .navigationDestination(isPresented: $viewModel.isLinkActive){
            HomeView()
        }
        .onAppear(){
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
    KeysignView(vault:Vault.example,
                keysignCommittee: [],
                mediatorURL: "",
                sessionID: "session",
                keysignType: .ECDSA,
                messsageToSign: ["message"],
                keysignPayload: nil)
}
