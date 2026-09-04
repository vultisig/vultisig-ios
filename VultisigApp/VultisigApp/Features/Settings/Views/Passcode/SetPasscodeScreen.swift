//
//  SetPasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Two steps: choose a passcode, then confirm it. A mismatch keeps the original
/// entry visible and clears only the confirmation row for another attempt.
struct SetPasscodeScreen: View {

    @StateObject private var viewModel = PasscodeViewModel(stage: .new)
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
                title: "passcodeSetSheetTitle".localized,
                subtitle: viewModel.stage == .confirm ? nil : "passcodeChooseGuidance".localized,
                completedPasscode: viewModel.stage == .confirm ? viewModel.firstEntry : nil,
                activePrompt: viewModel.stage == .confirm ? "passcodeConfirmSheetTitle".localized : nil,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                isSuccess: viewModel.completion == .success,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.submitForSet() }
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
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func finishPresentation() {
        if viewModel.completion == .cancelledByLock {
            isPresented = false
            return
        }

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }
}
