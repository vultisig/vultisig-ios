//
//  Keygen.swift
//  VultisigApp
//

import CryptoKit
import Foundation
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
    let keyImportInput: KeyImportInput?
    let isInitiateDevice: Bool
    @Binding var hideBackButton: Bool

    @StateObject var viewModel = KeygenViewModel()

    @State var progressCounter: Double = 1
    @State var showProgressRing = true
    @State var showDoneText = false
    @State var showError = false
    @State var showVerificationView = false
    @State var vaultCreatedAnimationVM: RiveViewModel? = nil
    @State var checkmarkAnimationVM: RiveViewModel? = nil

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Environment(\.router) var router

    var body: some View {
        content
            .sensoryFeedback(.success, trigger: showDoneText)
            .sensoryFeedback(.error, trigger: showError)
            .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.status)
            .onChange(of: viewModel.isLinkActive) { _, isActive in
                guard isActive else { return }
                handleNavigation()
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

    private func handleNavigation() {
        switch tssType {
        case .Migrate:
            router.navigate(to: KeygenRoute.backupNow(
                tssType: tssType,
                backupType: .single(vault: vault),
                isNewVault: true
            ))
        case .KeyImport, .Keygen, .Reshare:
            if fastSignConfig != nil {
                router.navigate(to: KeygenRoute.keyImportOverview(
                    tssType: tssType,
                    vault: vault,
                    email: fastSignConfig?.email,
                    keyImportInput: keyImportInput,
                    setupType: .fast
                ))
            } else {
                router.navigate(to: KeygenRoute.reviewYourVaults(
                    vault: vault,
                    tssType: tssType,
                    keygenCommittee: keygenCommittee,
                    email: nil,
                    keyImportInput: keyImportInput,
                    isInitiateDevice: isInitiateDevice
                ))
            }
        }
    }

    var content: some View {
        container
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onLoad {
                Task {
                    await setData()
                    await viewModel.startKeygen(context: context)
                }
            }
            #if os(iOS)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            #endif
            .alert(
                NSLocalizedString("vaultAlreadyExists", comment: ""),
                isPresented: $viewModel.showDuplicateVaultAlert
            ) {
                Button(NSLocalizedString("replaceExistingVault", comment: ""), role: .destructive) {
                    viewModel.resolveDuplicateVault(shouldReplace: true)
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
                    viewModel.resolveDuplicateVault(shouldReplace: false)
                }
            } message: {
                Text(
                    String(
                        format: NSLocalizedString("duplicateVaultMessage", comment: ""),
                        viewModel.duplicateVaultName
                    )
                )
            }
            .onChange(of: viewModel.didCancelDuplicateVault) { _, didCancel in
                if didCancel {
                    router.navigateToRoot()
                }
            }
    }

    var container: some View {
        ZStack {
            states
                .opacity(tssType == .Migrate ? 0 : 1)

            if tssType == .Migrate {
                if viewModel.status == .KeygenFailed {
                    migrationFailedText
                } else {
                    migrateView
                }
            }
        }
        .ignoresSafeArea()
    }

    var migrateView: some View {
        UpgradingVaultView()
    }

    var states: some View {
        ZStack {
            switch viewModel.status {
            case .CreatingInstance,
                    .KeygenECDSA,
                    .KeygenEdDSA,
                    .ReshareECDSA,
                    .ReshareEdDSA:
                KeygenAnimationView(
                    isFast: fastSignConfig != nil,
                    connected: $viewModel.keygenConnected,
                    progress: $viewModel.progress
                )
            case .KeygenFinished:
                doneText
            case .KeygenFailed:
                keygenFailedView
            }
        }
    }

    var migrationFailedText: some View {
        ErrorView(
            type: .alert,
            title: "migrationFailed".localized,
            description: viewModel.keygenError,
            buttonTitle: "retry".localized
        ) {
            dismiss()
        }
        .onAppear {
            showError = true
        }
    }

    var doneText: some View {
        ZStack {
            vaultCreatedAnimationVM?.view()
                .frame(maxWidth: 512)
                .offset(y: -120)

            VStack(spacing: 24) {
                VStack {
                    Text(NSLocalizedString("vaultCreated", comment: ""))
                        .foregroundColor(Theme.colors.textPrimary)
                    Text(NSLocalizedString("successfully", comment: ""))
                        .foregroundStyle(LinearGradient.primaryGradient)
                }
                .font(Theme.fonts.title1)
                .opacity(progressCounter == 4 ? 1 : 0)
                .animation(.easeInOut, value: progressCounter)
                .padding(.top, 60)

                checkmarkAnimationVM?.view()
                    .frame(width: 80, height: 80)
            }
            .offset(y: 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.colors.bgPrimary)
        .onAppear {
            setDoneData()
        }
    }

    var keygenFailedView: some View {
        ZStack {
            switch tssType {
            case .Keygen, .KeyImport:
                keygenFailedText
            case .Reshare:
                keygenReshareFailedText
            case .Migrate:
                migrateFailedText
            }
        }
        .onAppear {
            showError = true
            hideBackButton = false
            showProgressRing = false
        }
    }

    var migrateFailedText: some View {
        ErrorView(
            type: .alert,
            title: "migrationFailed".localized,
            description: viewModel.keygenError,
            buttonTitle: "retry".localized
        ) {
            dismiss()
        }
    }

    var keygenFailedText: some View {
        ErrorView(
            type: .alert,
            title: "keygenFailed".localized,
            description: viewModel.keygenError,
            buttonTitle: "retry".localized
        ) {
            dismiss()
        }
    }

    var keygenReshareFailedText: some View {
        ErrorMessage(text: "thresholdNotReachedMessage", width: 300)
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
            initiateDevice: isInitiateDevice,
            keyImportInput: keyImportInput
        )
    }

    private func setDoneData() {
        showDoneText = true
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
        if fastSignConfig != nil {
            showVerificationView = true
        }
    }

}

#Preview("keygen") {
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
        keyImportInput: nil,
        isInitiateDevice: false,
        hideBackButton: .constant(false)
    )
    .frame(maxWidth: 600, maxHeight: isMacOS ? 600 : .infinity)
    .background(Theme.colors.bgPrimary)
}
