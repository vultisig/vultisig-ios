//
//  EnterPasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// The lock screen. Presented over everything when the app is locked, with no
/// navigation bar and no way past it other than the passcode.
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
        Screen {
            // Same logo, same gradient, in the same place as the entry view puts
            // it — so the biometric attempt happens over what looks like the
            // privacy cover rather than over a keypad that is about to vanish.
            if viewModel.shouldPresentEntry {
                PasscodeEntryView(
                    title: "passcodeEnterTitle".localized,
                    subtitle: "passcodeEnterSubtitle".localized,
                    errorMessage: viewModel.errorMessage,
                    isBusy: viewModel.isBusy,
                    showsLogo: true,
                    passcode: $viewModel.entry,
                    onComplete: { _ in
                        Task {
                            await viewModel.unlock()
                            guard !viewModel.didFinish else { return }
                            onAttemptFailed()
                        }
                    }
                )
            } else {
                awaitingBiometrics
            }
        }
        .screenNavigationBarHidden(true)
        .screenBackground(.gradient)
        .accessibilityIdentifier(AccessibilityID.Passcode.enterScreen)
        .task {
            await viewModel.beginUnlock(biometricReason: "passcodeBiometricReason".localized)
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            onUnlocked()
        }
    }

    /// What the lock screen is while it is deciding whether it needs to exist.
    ///
    /// Deliberately not a spinner. Nothing is loading — the app is guarding
    /// itself — and a progress indicator would promise the user that waiting
    /// achieves something. The logo is also what `CoverView` shows on the way
    /// out, so backgrounding and returning look like one continuous screen
    /// instead of a cover, a keypad and a dismissal.
    private var awaitingBiometrics: some View {
        Image("vultisig-logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(AccessibilityID.Passcode.awaitingBiometrics)
    }
}
