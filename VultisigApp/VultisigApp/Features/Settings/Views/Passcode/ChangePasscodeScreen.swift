//
//  ChangePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Three steps: current, new, confirm. The current passcode is verified before
/// the user is asked to invent a replacement, so a wrong one is reported
/// immediately rather than after three screens of typing.
struct ChangePasscodeScreen: View {

    @StateObject private var viewModel = PasscodeViewModel(stage: .current)
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
                    Task { await viewModel.submitForChange() }
                }
            )
        }
        .screenTitle("passcodeChangeTitle".localized)
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            dismiss()
        }
    }

    private var title: String {
        switch viewModel.stage {
        case .current:
            return "passcodeCurrentTitle".localized
        case .new:
            return "passcodeNewTitle".localized
        case .confirm:
            return "passcodeConfirmTitle".localized
        }
    }

    private var subtitle: String {
        switch viewModel.stage {
        case .current:
            return "passcodeCurrentSubtitle".localized
        case .new:
            return "passcodeChooseSubtitle".localized
        case .confirm:
            return "passcodeConfirmSubtitle".localized
        }
    }
}
