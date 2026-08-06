//
//  SetPasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Two steps: choose a passcode, then confirm it. A mismatch sends the user back
/// to choosing rather than silently accepting the second entry.
struct SetPasscodeScreen: View {

    @StateObject private var viewModel = PasscodeViewModel(stage: .new)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen {
            PasscodeEntryView(
                title: title,
                subtitle: subtitle,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.submitForSet() }
                }
            )
        }
        .screenTitle("passcodeSetTitle".localized)
        .screenBackground(.gradient)
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            dismiss()
        }
    }

    private var title: String {
        viewModel.stage == .confirm
            ? "passcodeConfirmTitle".localized
            : "passcodeChooseTitle".localized
    }

    private var subtitle: String {
        viewModel.stage == .confirm
            ? "passcodeConfirmSubtitle".localized
            : "passcodeChooseSubtitle".localized
    }
}
