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

    var body: some View {
        Screen {
            PasscodeEntryView(
                title: "passcodeEnterTitle".localized,
                subtitle: "passcodeEnterSubtitle".localized,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.unlock() }
                }
            )
        }
        .screenNavigationBarHidden(true)
        .accessibilityIdentifier(AccessibilityID.Passcode.enterScreen)
        .task {
            await viewModel.refreshBiometricAvailability()
            guard viewModel.isBiometricUnlockAvailable else { return }
            // Offered immediately so the common case is one glance rather than
            // five taps. Declining or failing leaves the passcode field ready.
            await viewModel.unlockWithBiometrics(reason: "passcodeBiometricReason".localized)
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            onUnlocked()
        }
    }
}
