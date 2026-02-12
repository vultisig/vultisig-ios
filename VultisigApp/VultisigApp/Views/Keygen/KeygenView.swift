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

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    @State var progressCounter: Double = 1
    @State var showProgressRing = true
    @State var showDoneText = false
    @State var showError = false
    @State var showVerificationView = false
    @State var vaultCreatedAnimationVM: RiveViewModel? = nil
    @State var checkmarkAnimationVM: RiveViewModel? = nil
    @State var keygenAnimationVM: RiveViewModel? = nil
    @State var keygenAnimationVMInstance: RiveDataBindingViewModel.Instance?
    @State var displayedProgress: Float = 0
    @State var progressAnimationTimer: Timer?

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
                keygenAnimationVM = RiveViewModel(
                    fileName: fastSignConfig != nil ? "keygen_fast" : "keygen_secure",
                    autoPlay: true,
                )
                keygenAnimationVM?.fit = .layout
                keygenAnimationVM?.layoutScaleFactor = RiveViewModel.layoutScaleFactorAutomatic
                keygenAnimationVM?.riveModel?.enableAutoBind { instance in
                    keygenAnimationVMInstance = instance
                }
            }
            .onDisappear {
                vaultCreatedAnimationVM?.stop()
                progressAnimationTimer?.invalidate()
                progressAnimationTimer = nil
            }
            .onChange(of: keygenAnimationVMInstance) { _, instance in
                let connected = instance?.booleanProperty(fromPath: "Connected")
                connected?.value = true
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
                keygenAnimationVM?.view()
                    .ignoresSafeArea()
                    .readSize { size in
                        let posXcircles = keygenAnimationVMInstance?.numberProperty(fromPath: "posXcircles")
                        posXcircles?.value = Float(size.width / 2)
                    }
                    .onChange(of: viewModel.progress) { _, newValue in
                        animateProgress(to: newValue)
                    }
                    .onAppear {
                        #if os(iOS)
                        HapticFeedbackManager.shared.playAHAPFile(named: "keygen_animation_haptic", looping: true)
                        #endif
                    }
                    .onDisappear {
                        #if os(iOS)
                        HapticFeedbackManager.shared.stopAHAPPlayback()
                        #endif
                    }
            case .KeygenFinished:
                doneText
            case .KeygenFailed:
                keygenFailedView
            }
        }
    }

    var migrationFailedText: some View {
        VStack(spacing: 32) {
            Spacer()
            ErrorMessage(text: viewModel.keygenError)
            Spacer()
            appVersion
            migrateRetryButton
        }
        .padding(32)
        .onAppear {
            showError = true
        }
    }

    var migrateRetryButton: some View {
        PrimaryButton(title: "retry") {
            dismiss()
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
        VStack(spacing: 18) {
            Text(NSLocalizedString("migrationFailed", comment: "migration failed"))
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(viewModel.keygenError)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
        }
    }

    var keygenFailedText: some View {
        VStack(spacing: 18) {
            Text(NSLocalizedString("keygenFailed", comment: "key generation failed"))
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(viewModel.keygenError)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
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
        .font(Theme.fonts.bodySRegular)
        .foregroundColor(Theme.colors.bgButtonPrimary)
    }

    var button: some View {
        PrimaryButton(title: "retry") {
            dismiss()
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

    private func animateProgress(to targetValue: Float) {
        progressAnimationTimer?.invalidate()

        let duration: TimeInterval = 3.0
        let frameRate: TimeInterval = 1.0 / 60.0
        let totalSteps = Int(duration / frameRate)
        let startValue = displayedProgress
        let delta = targetValue - startValue

        guard delta != 0, totalSteps > 0 else {
            displayedProgress = targetValue
            updateRiveProgress(targetValue)
            return
        }

        var currentStep = 0

        progressAnimationTimer = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true) { timer in
            currentStep += 1
            let progress = Float(currentStep) / Float(totalSteps)
            // Ease-out curve for smoother deceleration
            let easedProgress = 1 - pow(1 - progress, 3)
            let newValue = startValue + delta * easedProgress

            displayedProgress = newValue
            updateRiveProgress(newValue)

            if currentStep >= totalSteps {
                timer.invalidate()
                progressAnimationTimer = nil
                displayedProgress = targetValue
                updateRiveProgress(targetValue)
            }
        }
    }

    private func updateRiveProgress(_ value: Float) {
        let progressProperty = keygenAnimationVMInstance?.numberProperty(fromPath: "progessPercentage")
        progressProperty?.value = value
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
