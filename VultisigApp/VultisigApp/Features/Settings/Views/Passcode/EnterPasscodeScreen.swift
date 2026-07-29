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
                showsLogo: true,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.unlock() }
                }
            )
        }
        .screenNavigationBarHidden(true)
        .screenBackground(.gradient)
        .accessibilityIdentifier(AccessibilityID.Passcode.enterScreen)
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            onUnlocked()
        }
    }
}
