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
        content
            .accessibilityIdentifier(AccessibilityID.Passcode.enterScreen)
            .task {
                await viewModel.beginUnlock(biometricReason: "passcodeBiometricReason".localized)
            }
            .onChange(of: viewModel.didFinish) { _, finished in
                guard finished else { return }
                onUnlocked()
            }
    }

    /// Two screens, not one screen with two states — and the difference is
    /// structural rather than cosmetic. The waiting half is
    /// ``VultisigBrandScreen`` at the **top level**: putting it inside `Screen`
    /// like the keypad would inset it for the safe area and move the logo up the
    /// display relative to the privacy cover it takes over from, which is a jump
    /// exactly where there should be no seam at all.
    @ViewBuilder
    private var content: some View {
        if viewModel.shouldPresentEntry {
            entry
        } else {
            VultisigBrandScreen()
                .accessibilityIdentifier(AccessibilityID.Passcode.awaitingBiometrics)
        }
    }

    private var entry: some View {
        Screen {
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
        }
        .screenNavigationBarHidden(true)
        .screenBackground(.gradient)
    }
}
