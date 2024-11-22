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
    let vault: Vault
    let tssType: TssType // keygen or reshare
    let keygenCommittee: [String]
    let vaultOldCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let encryptionKeyHex: String
    let oldResharePrefix: String
    let fastSignConfig: FastSignConfig?
    @Binding var hideBackButton: Bool
    
    var selectedTab: SetupVaultState? = nil

    @StateObject var viewModel = KeygenViewModel()
    
    let progressTotalCount: Double = 4
    
    @State var progressCounter: Double = 1
    @State var showProgressRing = true
    @State var showVerificationView = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
    var body: some View {
        content
            .navigationDestination(isPresented: $viewModel.isLinkActive) {
                navigationDestination
            }
            .onAppear {
                hideBackButton = true
                dismissView()
            }
    }
    
    var fields: some View {
        VStack(spacing: 0) {
            Spacer()
            if showProgressRing {
                progress
            }
            states
            Spacer()
            keygenViewInstructions
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
            maxHeight: showProgressRing ? 50 : .infinity
        )
        .offset(y: -20)
    }
    
    var progress: some View {
        ProgressRing(progress: Double(progressCounter/progressTotalCount))
    }
    
    var instructions: some View {
        WifiInstruction()
            .padding(.vertical, 20)
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
                setDoneData()
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
            hideBackButton = false
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
    
    var navigationDestination: some View {
        ZStack {
            if showVerificationView {
                ServerBackupVerificationView(
                    vault: vault,
                    viewModel: viewModel
                )
            } else {
                BackupVaultNowView(vault: vault)
            }
        }
    }
    
    func setData() async {
        await viewModel.setData(
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
    
    private func setDoneData() {
        checkVaultType()
        
        if tssType == .Reshare {
            vault.isBackedUp = false
        }

        if let fastSignConfig {
            viewModel.saveFastSignConfig(fastSignConfig, vault: vault)
        }

        progressCounter = 4
        viewModel.delaySwitchToMain()
    }
    
    private func checkVaultType() {
        if let selectedTab, selectedTab == .fast {
            showVerificationView = true
        }
    }
    
    private func dismissView() {
        guard viewModel.setupLinkActive else {
            return
        }
        
        deleteVault()
    }
    
    func deleteVault() {
        context.delete(vault)
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("Error: \(error)")
        }
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
            oldResharePrefix: "",
            fastSignConfig: nil,
            hideBackButton: .constant(false),
            selectedTab: SetupVaultState.active
        )
        .environmentObject(SettingsDefaultChainViewModel())
    }
    .frame(height: 600)
}
