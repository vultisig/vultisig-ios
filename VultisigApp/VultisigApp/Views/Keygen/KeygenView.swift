//
//  Keygen.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import Mediator
import OSLog
import SwiftData
import SwiftUI
import Tss

struct KeygenView: View {
    private let logger = Logger(subsystem: "keygen", category: "tss")
    @Environment(\.modelContext) private var context
    let vault: Vault
    let tssType: TssType // keygen or reshare
    let keygenCommittee: [String]
    let vaultOldCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let encryptionKeyHex: String
    let oldResharePrefix: String
    @StateObject var viewModel = KeygenViewModel()
    
    let progressTotalCount: Double = 4
    
    @State var progressCounter: Double = 0
    @State var showProgressRing = true
    
    var body: some View {
        VStack {
            Spacer()
            content
            Spacer()
            instructions
        }
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $viewModel.isLinkActive) {
            HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
        }
        .task {
            await viewModel.startKeygen(context: context)
        }
#if os(iOS)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            setData()
        }
        .onDisappear(){
            UIApplication.shared.isIdleTimerDisabled = false
        }
#endif
    }
    
    var content: some View {
        ZStack {
            states
            
            if showProgressRing {
                progress
            }
        }
    }
    
    var states: some View {
        ZStack {
            switch viewModel.status {
            case .CreatingInstance:
                preparingVaultText
            case .KeygenECDSA:
                generatingECDSAText
            case .KeygenEdDSA:
                generatingEdDSAText
            case .ReshareECDSA:
                reshareECDSAText
            case .ReshareEdDSA:
                reshareEdDSAText
            case .KeygenFinished:
                doneText
            case .KeygenFailed:
                keygenFailedView
            }
        }
        .frame(
            maxWidth: showProgressRing ? 280 : .infinity,
            maxHeight: showProgressRing ? 280 : .infinity
        )
    }
    
    var progress: some View {
        ProgressRing(progress: Double(progressCounter/progressTotalCount))
    }
    
    var instructions: some View {
        WifiInstruction()
            .padding(.bottom, 80)
    }
    
    var preparingVaultText: some View {
        KeygenStatusText(status: NSLocalizedString("preparingVault", comment: "PREPARING VAULT..."))
            .onAppear {
                progressCounter = 1
            }
    }
    
    var generatingECDSAText: some View {
        KeygenStatusText(status: NSLocalizedString("generatingECDSA", comment: "GENERATING ECDSA KEY"))
            .onAppear {
                progressCounter = 2
            }
    }
    
    var generatingEdDSAText: some View {
        KeygenStatusText(status: NSLocalizedString("generatingEdDSA", comment: "GENERATING EdDSA KEY"))
            .onAppear {
                progressCounter = 3
            }
    }
    
    var reshareECDSAText: some View {
        KeygenStatusText(status: NSLocalizedString("reshareECDSA", comment: "Resharing ECDSA KEY"))
            .onAppear {
                progressCounter = 2
            }
    }
    
    var reshareEdDSAText: some View {
        KeygenStatusText(status: NSLocalizedString("reshareEdDSA", comment: "Resharing EdDSA KEY"))
            .onAppear {
                progressCounter = 3
            }
    }
    
    var doneText: some View {
        Text("DONE")
            .foregroundColor(.backgroundBlue)
            .onAppear {
                progressCounter = 4
                viewModel.delaySwitchToMain()
            }
    }
    
    var keygenFailedView: some View {
        ZStack {
            switch tssType {
            case .Keygen:
                keygenFailedText
            case .Reshare:
                keygenReshareFailedText
            }
        }
        .onAppear {
            showProgressRing = false
        }
    }
    
    var keygenFailedText: some View {
        VStack(spacing: 18) {
            Text(NSLocalizedString("keygenFailed", comment: "key generation failed"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            Text(viewModel.keygenError)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }
    }
    
    var keygenReshareFailedText: some View {
        VStack(spacing: 18) {
            Text(NSLocalizedString("reshareFailed", comment: "Resharing key failed"))
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            Text(viewModel.keygenError)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }
    }
    
    private func setData() {
        viewModel.setData(
            vault: vault,
            tssType: tssType,
            keygenCommittee: keygenCommittee,
            vaultOldCommittee: vaultOldCommittee,
            mediatorURL: mediatorURL,
            sessionID: sessionID,
            encryptionKeyHex: encryptionKeyHex,
            oldResharePrefix: oldResharePrefix
        )
    }
}

#Preview("keygen") {
    ZStack {
        Background()
        KeygenView(
            vault: Vault.example,
            tssType: .Keygen,
            keygenCommittee: [],
            vaultOldCommittee: [],
            mediatorURL: "",
            sessionID: "",
            encryptionKeyHex: "",
            oldResharePrefix: ""
        )
    }
}
