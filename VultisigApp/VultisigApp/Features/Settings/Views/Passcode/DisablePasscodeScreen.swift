//
//  DisablePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Removing the passcode still requires entering it.
///
/// The subtitle says plainly what removal costs: the key shares are decrypted
/// again and the device goes back to exactly the state it was in before the
/// passcode. That is the point — it is a real inverse, so a backup taken
/// afterwards restores on any build — but it is protection genuinely coming off,
/// and the user has to be told so rather than reassured.
struct DisablePasscodeScreen: View {

    @StateObject private var viewModel = PasscodeViewModel(stage: .current)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen {
            PasscodeEntryView(
                title: "passcodeDisableTitle".localized,
                subtitle: "passcodeDisableSubtitle".localized,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.submitForDisable() }
                }
            )
        }
        .screenTitle("passcodeDisableNavTitle".localized)
        .screenBackground(.gradient)
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            dismiss()
        }
    }
}
