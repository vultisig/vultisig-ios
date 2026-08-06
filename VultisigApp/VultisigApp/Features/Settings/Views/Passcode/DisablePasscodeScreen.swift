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
        // A sheet is not a place you go back from. macOS would otherwise draw
        // `Screen`'s own back chevron here, which offers to return to a screen
        // that is still sitting behind this one; iOS has only the swipe, which
        // is invisible. Both get the close instead.
        //
        // It goes through `Screen`'s toolbar rather than a second
        // `.crossPlatformToolbar`, because `Screen` already renders one on
        // macOS and an outer toolbar stacks another row above it rather than
        // replacing it.
        .screenBackButtonHidden()
        .screenToolbar {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented = false
                }
            }
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            isPresented = false
        }
    }
}
