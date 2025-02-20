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
import RiveRuntime

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
    let isInitiateDevice: Bool
    @Binding var hideBackButton: Bool
    
    var selectedTab: SetupVaultState? = nil

    @StateObject var viewModel = KeygenViewModel()
    
    let progressTotalCount: Double = 4
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    
    @State var progressCounter: Double = 1
    @State var showProgressRing = true
    @State var showVerificationView = false
    @State var vaultCreatedAnimationVM: RiveViewModel? = nil
    @State var checkmarkAnimationVM: RiveViewModel? = nil
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
    var body: some View {
        content
            .navigationDestination(isPresented: $viewModel.isLinkActive) {
                if let fastSignConfig, showVerificationView {
                    FastBackupVaultOverview(
                        vault: vault,
                        selectedTab: selectedTab,
                        email: fastSignConfig.email,
                        viewModel: viewModel
                    )
                } else {
                    SecureBackupVaultOverview(vault: vault)
                }
            }
            .onAppear {
                hideBackButton = true
                vaultCreatedAnimationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
                checkmarkAnimationVM = RiveViewModel(fileName: "CreatingVaultCheckmark", autoPlay: true)
            }
            .onDisappear {
                vaultCreatedAnimationVM?.stop()
            }
    }
    
    var fields: some View {
        VStack(spacing: 12) {
            Spacer()
            if showProgressRing {
                if progressCounter<4 {
                    title
                }
                states
            }
            Spacer()
            
            if progressCounter < 4 {
                if viewModel.status == .KeygenFailed {
                    retryButton
                } else {
                    progressContainer
                }
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
    }
    
    var title: some View {
        Text(NSLocalizedString("whileYouWait", comment: "KEYGEN"))
            .foregroundColor(.extraLightGray)
            .font(.body16BrockmannMedium)
    }
    
    var instructions: some View {
        WifiInstruction()
            .padding(.vertical, 20)
    }
    
    var preparingVaultText: some View {
        KeygenStatusText(
            gradientText: "preparingVaultText1",
            plainText: "preparingVaultText2"
        )
        .onAppear {
            progressCounter = 1
        }
    }
    
    var generatingECDSAText: some View {
        KeygenStatusText(
            gradientText: "generatingECDSAText1",
            plainText: "generatingECDSAText2"
        )
        .onAppear {
            progressCounter = 2
        }
    }
    
    var generatingEdDSAText: some View {
        KeygenStatusText(
            gradientText: "generatingEdDSAText1",
            plainText: "generatingEdDSAText2"
        )
        .onAppear {
            progressCounter = 3
        }
    }
    
    var reshareECDSAText: some View {
        KeygenStatusText(
            gradientText: "",
            plainText: "reshareECDSA"
        )
        .onAppear {
            progressCounter = 2
        }
    }
    
    var reshareEdDSAText: some View {
        KeygenStatusText(
            gradientText: "",
            plainText: "reshareEdDSA"
        )
        .onAppear {
            progressCounter = 3
        }
    }
    
    var doneText: some View {
        VStack(spacing: 18) {
            vaultCreatedAnimationVM?.view()
                .scaleEffect(0.8)
                .frame(maxWidth: 512)
            
            VStack {
                Text(NSLocalizedString("vaultCreated", comment: ""))
                    .foregroundColor(.neutral0)
                Text(NSLocalizedString("successfully", comment: ""))
                    .foregroundStyle(LinearGradient.primaryGradient)
            }
            .font(.body28BrockmannMedium)
            .opacity(progressCounter == 4 ? 1 : 0)
            .animation(.easeInOut, value: progressCounter)
            .padding(.top, 60)
            
            checkmarkAnimationVM?.view()
                .frame(width: 80, height: 80)
        }
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
        ErrorMessage(text: "thresholdNotReachedMessage", width: 300)
    }
    
    var retryButton: some View {
        VStack(spacing: 32) {
            appVersion
            button
        }
        .padding(.horizontal, 16)
    }
    
    var appVersion: some View {
        return VStack {
            Text("Vultisig APP V\(version ?? "1")")
            Text("(Build \(build ?? "1"))")
        }
        .textCase(.uppercase)
        .font(.body14Menlo)
        .foregroundColor(.turquoise600)
    }
    
    var button: some View {
        Button {
            Task {
                await setData()
            }
        } label: {
            FilledButton(title: "retry")
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
            oldResharePrefix: oldResharePrefix,
            initiateDevice: isInitiateDevice
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
            isInitiateDevice: false,
            hideBackButton: .constant(false),
            selectedTab: SetupVaultState.active
        )
        .environmentObject(SettingsDefaultChainViewModel())
    }
    .frame(height: 600)
}
