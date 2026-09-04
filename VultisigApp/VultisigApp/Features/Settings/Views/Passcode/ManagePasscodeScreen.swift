//
//  ManagePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Settings entry point for the passcode: turn it on, change it, turn it off,
/// and reach the auto-lock interval once it is on.
struct ManagePasscodeScreen: View {

    @Environment(\.router) var router
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var isSet: Bool = false
    /// Raised by "Set passcode" instead of navigating, so the backup prompt is
    /// answered before the passcode screen is reached at all.
    ///
    /// An *item* rather than a flag, because both answers end in a navigation
    /// push and only `crossPlatformSheet(item:onDismiss:)` can run one after the
    /// dismissal has settled. Pushing while the sheet is still on screen races
    /// the dismissal animation and the destination can be dropped.
    @State private var backupPrompt: BackupPrompt?
    /// Which button was pressed, held until the sheet is off screen.
    @State private var backupPromptAnswer: BackupPromptAnswer?
    @State private var isBiometricEnabled: Bool = false
    @State private var biometricAvailability: BiometricAvailability = .available
    @State private var biometricError: String?
    @State private var activePasscodeFlow: PasscodeFlow?
    @State private var isPasscodeOperationInFlight = false
    @State private var autoLockInterval: AutoLockInterval = .default
    @State private var bannerText: String?

    private let service: PasscodeService
    private let lockService: AppLockService

    init(
        service: PasscodeService = .shared,
        lockService: AppLockService = .shared
    ) {
        self.service = service
        self.lockService = lockService
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    passcodeGroup

                    if isSet {
                        biometricAndTimingGroup
                    }

                    if let biometricNote {
                        Text(biometricNote)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.alertError)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(AccessibilityID.Settings.biometricUnlockNote)
                    }

                }
            }
        }
        .screenTitle("security".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        .withBanner(text: $bannerText)
        .crossPlatformSheet(
            isPresented: isPasscodeFlowPresented,
            isDismissable: !isPasscodeOperationInFlight
        ) {
            if let activePasscodeFlow {
                passcodeScreen(for: activePasscodeFlow)
            }
        }
        // Dismissable on purpose. Backing out of it is backing out of setting a
        // passcode at all, which leaves the key shares exactly as they are — the
        // one outcome here that cannot cost anyone their funds, and it answers
        // nothing so `onDismiss` has nothing to carry out.
        .crossPlatformSheet(item: $backupPrompt, onDismiss: actOnBackupPromptAnswer) { _ in
            BackUpBeforePasscodeScreen(
                isPresented: Binding(
                    get: { backupPrompt != nil },
                    set: { isPresented in
                        guard !isPresented else { return }
                        backupPrompt = nil
                    }
                ),
                onBackUpNow: { answerBackupPrompt(with: .backUp) },
                onContinue: { answerBackupPrompt(with: .alreadyHasBackup) }
            )
        }
        // `.onAppear` as well as `.task`: returning from the pushed set/change
        // screens does not re-run `.task`, and a stale `isSet` would keep
        // offering "Set passcode" after one had just been set.
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        // And the navigation path on top of both, but only where the two above
        // are not enough: on macOS neither lifecycle callback fires when a
        // pushed screen pops, and this view is not torn down either, so it keeps
        // the `isSet` it was built with and goes on offering "Set passcode" over
        // a passcode that now exists. The path is the one thing that provably
        // changes when the set or change screen dismisses itself, and it is
        // published, so a live subscription hears the return whether or not the
        // view is told it reappeared.
        //
        // Confined to macOS because it is not free: `Published` replays on
        // subscribe and fires again for every push and pop anywhere in the
        // stack, so on iOS — where `.onAppear` already works — it would only add
        // Keychain and biometry reads for a screen that is often not on top.
        #if os(macOS)
        .onReceive(router.$navPath) { _ in
            Task { await refresh() }
        }
        #endif
        .onChange(of: activePasscodeFlow) { _, flow in
            guard flow == nil else { return }
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLockBackupCompleted)) { _ in
            bannerText = "backupSaved".localized
        }
    }

    private var passcodeGroup: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "appLockPasscodeTitle".localized,
                isOn: Binding(
                    get: { isSet },
                    set: { requestedValue in
                        if requestedValue {
                            backupPrompt = BackupPrompt()
                        } else {
                            activePasscodeFlow = .disable
                        }
                    }
                )
            )

            if isSet {
                divider
                actionRow(title: "passcodeChangeTitle".localized) {
                    activePasscodeFlow = .change
                }
            }
        }
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.xl.shape)
    }

    private var biometricAndTimingGroup: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: biometricTitle,
                isOn: Binding(
                    get: { isBiometricEnabled },
                    set: { newValue in Task { await setBiometric(enabled: newValue) } }
                )
            )
            .accessibilityIdentifier(AccessibilityID.Settings.biometricUnlockToggle)

            divider

            actionRow(
                title: "lockAfterTitle".localized,
                trailingTitle: autoLockInterval.titleKey.localized
            ) {
                router.navigate(to: SettingsRoute.autoLock)
            }
        }
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.xl.shape)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.colors.primaryAccent4)
                .fixedSize()
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private func actionRow(
        title: String,
        trailingTitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                Spacer()

                if let trailingTitle {
                    Text(trailingTitle)
                        .font(Theme.fonts.bodyMRegular)
                        .foregroundStyle(Theme.colors.textSecondary)
                } else {
                    Icon(.chevronRightSmall, color: Theme.colors.textSecondary, size: 16)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.colors.borderLight)
            .frame(height: 1)
    }

    private var isPasscodeFlowPresented: Binding<Bool> {
        Binding(
            get: { activePasscodeFlow != nil },
            set: { isPresented in
                guard !isPresented else { return }
                activePasscodeFlow = nil
            }
        )
    }

    @ViewBuilder
    private func passcodeScreen(for flow: PasscodeFlow) -> some View {
        switch flow {
        case .set:
            SetPasscodeScreen(
                isPresented: isPasscodeFlowPresented,
                isOperationInFlight: $isPasscodeOperationInFlight
            )
        case .change:
            ChangePasscodeScreen(
                isPresented: isPasscodeFlowPresented,
                isOperationInFlight: $isPasscodeOperationInFlight
            )
        case .disable:
            DisablePasscodeScreen(
                isPresented: isPasscodeFlowPresented,
                isOperationInFlight: $isPasscodeOperationInFlight
            )
        }
    }

    /// What the biometric row currently has to say for itself, if anything.
    ///
    /// The standing reason comes first and does not need a tap to find: a device
    /// with nothing enrolled cannot hold the shortcut, and letting someone
    /// discover that only by flipping a switch that flips back is the behaviour
    /// this screen was reported for. A failure from an actual attempt replaces
    /// it, because that one is about what just happened.
    private var biometricNote: String? {
        if let biometricError { return biometricError }
        guard isSet else { return nil }

        switch biometricAvailability {
        case .available:
            return nil
        case .notEnrolled:
            return "passcodeBiometricNotEnrolled".localized
        case .unavailable:
            return "passcodeBiometricNotAvailable".localized
        }
    }

    /// Presence is what presents the backup prompt; it carries nothing, because
    /// the answer travels separately and outlives the dismissal.
    struct BackupPrompt: Identifiable, Equatable {
        let id = UUID()
    }

    enum BackupPromptAnswer {
        case backUp
        case alreadyHasBackup
    }

    enum PasscodeFlow: Equatable {
        case set
        case change
        case disable
    }

    private var biometricTitle: String {
        #if os(macOS)
        return "touchIDUnlockTitle".localized
        #else
        switch appViewModel.authenticationType {
        case .FaceID:
            return "faceIDUnlockTitle".localized
        case .TouchID:
            return "touchIDUnlockTitle".localized
        case .OpticID, .None:
            return "biometricUnlockTitle".localized
        }
        #endif
    }

    /// Records the answer and closes the sheet. Acting on it waits for
    /// ``actOnBackupPromptAnswer()``.
    private func answerBackupPrompt(with answer: BackupPromptAnswer) {
        backupPromptAnswer = answer
        backupPrompt = nil
    }

    /// Carries out the answer, once the sheet is actually off screen.
    ///
    /// Both destinations are navigation pushes, and a push issued while the
    /// sheet is still dismissing can be dropped — which is why the prompt is an
    /// item-based sheet at all.
    private func actOnBackupPromptAnswer() {
        guard let answer = backupPromptAnswer else { return }
        backupPromptAnswer = nil

        switch answer {
        case .backUp:
            // The passcode seals the key shares of *every* stored vault, not
            // just the selected one, so the destination is the backup
            // **selection** screen — the one entry point that can export more
            // than the current vault. Which vaults to take is left to the user
            // there rather than decided here.
            guard let vault = appViewModel.selectedVault else {
                // No vault means nothing to export and nothing to lose, so the
                // prompt has nothing to offer. Falling through to the passcode
                // screen beats a button that does nothing.
                activePasscodeFlow = .set
                return
            }
            router.navigate(to: VaultRoute.backupSelection(
                vault: vault,
                origin: .appLockSettings
            ))
        case .alreadyHasBackup:
            // Taken at face value deliberately: `Vault.isBackedUp` is set by any
            // export or import and never cleared when the vault changes
            // afterwards, so it can neither confirm this answer nor contradict
            // it. Recording it as if it could would put a claim in the store
            // that later code might trust.
            activePasscodeFlow = .set
        }
    }

    private func setBiometric(enabled: Bool) async {
        // Moved before the call, so the switch follows the finger instead of
        // snapping back for the length of a Keychain round trip and then
        // returning. `refresh()` below overwrites it with what actually
        // happened, so an optimistic value can never outlive the attempt.
        isBiometricEnabled = enabled
        biometricError = nil

        if enabled {
            // Enabling needs the data key in hand, so it can only be done while
            // unlocked. A failure leaves the toggle off rather than implying a
            // shortcut exists — and now says why, which is the whole of this
            // change: every one of these used to be swallowed, so a device with
            // nothing enrolled produced a switch that returned to off and no
            // explanation anywhere.
            do {
                try await service.enableBiometricUnlock()
            } catch {
                biometricError = Self.message(for: error)
            }
        } else {
            // A failure here leaves the copy in place, so the toggle must not
            // claim it is gone. `refresh()` re-reads it either way.
            do {
                try await service.disableBiometricUnlock()
            } catch {
                biometricError = "passcodeBiometricDisableFailed".localized
            }
        }
        await refresh()
    }

    /// Says what the user has to do, where there is anything they can do.
    @MainActor
    private static func message(for error: Error) -> String {
        switch error as? BiometricUnlockError {
        case .notEnrolled:
            return "passcodeBiometricNotEnrolled".localized
        case .unavailable:
            return "passcodeBiometricNotAvailable".localized
        default:
            break
        }

        // A passcode-side refusal is not about biometry at all — the app locked
        // mid-flight, or another transition holds the lease — and
        // `PasscodeViewModel` already has the wording for those.
        if let passcodeError = error as? PasscodeError {
            return PasscodeViewModel.message(for: passcodeError)
        }

        return "passcodeBiometricEnableFailed".localized
    }

    private func refresh() async {
        isSet = await service.isSet
        isBiometricEnabled = await service.isBiometricUnlockEnabled
        biometricAvailability = await service.biometricAvailability
        autoLockInterval = lockService.autoLockInterval
        appViewModel.getBiometricType()
    }
}
