//
//  KeyboardDoneButton.swift
//  VultisigApp
//

#if os(iOS)
import SwiftUI

/// Dismisses the keyboard from a `.keyboard` toolbar.
///
/// From iOS 26 this is the system confirm (checkmark) button, because its width
/// does not depend on the translation. A text label beside the swap percentage
/// buttons overflows the glass toolbar on phones narrower than 440pt ("Concluído"
/// even on iOS 26.5), and UIKit then moves Done into the `⋯` menu.
struct KeyboardDoneButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .confirm, action: action)
        } else {
            Button(action: action) {
                Text("done".localized)
            }
        }
    }

    /// Whether a `Spacer` can sit between wide leading content and this button.
    /// From iOS 26 the spacer splits the toolbar into two glass groups, and iOS 27's
    /// margins around them no longer fit beside the swap percentage buttons.
    static var spacerFitsBesideWideContent: Bool {
        if #available(iOS 26.0, *) {
            return false
        }
        return true
    }
}
#endif
