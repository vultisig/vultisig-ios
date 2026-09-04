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

    /// Closing is done by the presenter's flag rather than `@Environment(\.dismiss)`.
    ///
    /// Below macOS 26 `crossPlatformSheet` is not a presentation at all — it
    /// renders this view as a sibling inside the presenter's own `ZStack` — so
    /// there is nothing there for `dismiss()` to close, and it would reach past
    /// this screen to the enclosing navigation stack instead. The flag is the
    /// one thing both sheet implementations agree on.
    @Binding var isPresented: Bool

    /// Mirrors the removal being in flight up to the presenter, which is the
    /// only place that can refuse the swipe and the backdrop tap.
    ///
    /// Removal rewrites every stored key share. Walking out of it does not
    /// cancel it — the work is an unstructured task that outlives this screen —
    /// it only means the settings list refreshes while the passcode is still
    /// there and never hears that it went, so it goes on offering to change a
    /// passcode that no longer exists.
    @Binding var isOperationInFlight: Bool
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Screen {
            PasscodeEntryView(
                title: "passcodeDisableTitle".localized,
                subtitle: "passcodeDisableSubtitle".localized,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                isSuccess: viewModel.completion == .success,
                passcode: $viewModel.entry,
                onComplete: { _ in
                    Task { await viewModel.submitForDisable() }
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

    private func finishPresentation() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }
}
