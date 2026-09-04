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
    @Binding var isPresented: Bool
    @Binding var isOperationInFlight: Bool
    @State private var dismissTask: Task<Void, Never>?

    init(
        isPresented: Binding<Bool>,
        isOperationInFlight: Binding<Bool>
    ) {
        _isPresented = isPresented
        _isOperationInFlight = isOperationInFlight
    }

    var body: some View {
        Screen {
            PasscodeEntryView(
                title: title,
                subtitle: subtitle,
                completedPasscode: viewModel.stage == .confirm ? viewModel.firstEntry : nil,
                activePrompt: viewModel.stage == .confirm ? "passcodeConfirmSheetTitle".localized : nil,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                isSuccess: viewModel.completion == .success,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.submitForChange() }
                }
            )
        }
        .passcodeSheetChrome(
            isPresented: $isPresented,
            isBusy: $isOperationInFlight
        )
        .onChange(of: viewModel.isBusy) { _, isBusy in
            isOperationInFlight = isBusy
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            finishPresentation()
        }
        .onDisappear { dismissTask?.cancel() }
    }

    private var title: String {
        switch viewModel.stage {
        case .current:
            return "passcodeCurrentTitle".localized
        case .new:
            return "passcodeNewTitle".localized
        case .confirm:
            return "passcodeNewTitle".localized
        }
    }

    private var subtitle: String? {
        switch viewModel.stage {
        case .current:
            return "passcodeCurrentSubtitle".localized
        case .new:
            return "passcodeChooseSubtitle".localized
        case .confirm:
            return nil
        }
    }

    private func finishPresentation() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }
}
