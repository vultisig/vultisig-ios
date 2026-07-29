//
//  DisablePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Removing the passcode still requires entering it.
///
/// The subtitle says plainly that key shares stay encrypted afterwards — the
/// passcode gates access to the key, it is not what provides the encryption, and
/// users should not believe they have just turned protection off.
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
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            dismiss()
        }
    }
}
