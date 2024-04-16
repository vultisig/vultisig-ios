//
//  Keygen.swift
//  VoltixApp
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
    @StateObject var viewModel = KeygenViewModel()
    
    let progressTotalCount = 4
    
    @State var progressCounter = 0
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
            HomeView()
        }
        .onAppear {
            setData()
        }
        .task {
            await viewModel.startKeygen(context: context)
        }
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
        let value = Double(progressCounter/progressTotalCount)
        return ProgressRing(progress: value)
    }
    
    var instructions: some View {
        WifiInstruction()
            .padding(.bottom, 80)
    }
    
    var preparingVaultText: some View {
        progressCounter += 1
        return KeygenStatusText(status: NSLocalizedString("preparingVault", comment: "PREPARING VAULT..."))
    }
    
    var generatingECDSAText: some View {
        progressCounter += 1
        return KeygenStatusText(status: NSLocalizedString("generatingECDSA", comment: "GENERATING ECDSA KEY"))
    }
    
    var generatingEdDSAText: some View {
        progressCounter += 1
        return KeygenStatusText(status: NSLocalizedString("generatingEdDSA", comment: "GENERATING EdDSA KEY"))
    }
    
    var reshareECDSAText: some View {
        showProgressRing = false
        return KeygenStatusText(status: NSLocalizedString("reshareECDSA", comment: "Resharing ECDSA KEY"))
    }
    
    var reshareEdDSAText: some View {
        showProgressRing = false
        return KeygenStatusText(status: NSLocalizedString("reshareEdDSA", comment: "Resharing EdDSA KEY"))
    }
    
    var doneText: some View {
        progressCounter += 1
        return EmptyView()
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
    }
    
    var keygenFailedText: some View {
        showProgressRing = false
        return VStack(spacing: 18) {
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
        showProgressRing = false
        return VStack(spacing: 18) {
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
            encryptionKeyHex: encryptionKeyHex
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
            encryptionKeyHex: ""
        )
    }
}
