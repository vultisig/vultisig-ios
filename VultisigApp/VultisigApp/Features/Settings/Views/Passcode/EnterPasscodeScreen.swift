//
//  EnterPasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// The lock screen. Presented over everything when the app is locked, with no
/// navigation bar and no way past it other than an explicit authentication.
struct EnterPasscodeScreen: View {

    @StateObject private var viewModel = PasscodeViewModel()
    let onUnlocked: () -> Void
    /// Reported after an attempt that did not open the app.
    ///
    /// `PasscodeService.unlockApp` repairs the lock mode when it finds the
    /// passcode confirmed gone, and this screen is who that repair is for:
    /// whoever is typing here is the user a completed disable trapped, and the
    /// error they were about to be shown is one no further entry can answer.
    /// Whether the gate may come down stays `AppViewModel`'s decision — this
    /// only reports that there is something to decide.
    let onAttemptFailed: () -> Void

    var body: some View {
        entry
            .accessibilityIdentifier(AccessibilityID.Passcode.enterScreen)
            .task {
                await viewModel.refreshBiometricAvailability()
            }
            .onChange(of: viewModel.didFinish) { _, finished in
                guard finished else { return }
                onUnlocked()
            }
    }

    private var entry: some View {
        LockPasscodeEntryView(
            errorMessage: viewModel.errorMessage,
            isBusy: viewModel.isBusy,
            isBiometricUnlockAvailable: viewModel.isBiometricUnlockAvailable,
            passcode: $viewModel.entry,
            onComplete: { _ in
                Task {
                    await viewModel.unlock()
                    guard !viewModel.didFinish else { return }
                    onAttemptFailed()
                }
            },
            onBiometricUnlock: {
                Task {
                    await viewModel.unlockWithBiometrics(
                        reason: "passcodeBiometricReason".localized
                    )
                }
            }
        )
    }
}
