//
//  DestinationTagTextField.swift
//  VultisigApp
//

import SwiftUI

/// Numeric input for the XRP destination tag. Mirrors `MemoTextField`'s
/// visual pattern; input is filtered to ASCII digits on both platforms
/// (bounds are enforced by the form validation, not here). Disabled state
/// (tag locked by an X-address) renders with secondary text color via the
/// standard `isEnabled` environment.
struct DestinationTagTextField: View {
    @Binding var destinationTag: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        container
            .font(Theme.fonts.bodyMMedium)
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.bgSurface2, lineWidth: 1)
            )
            .padding(1)
            .onChange(of: destinationTag) { _, newValue in
                let filtered = newValue.filter { $0.isASCII && $0.isNumber }
                if filtered != newValue {
                    destinationTag = filtered
                }
            }
    }

    var content: some View {
        HStack(spacing: 0) {
            textField
            Spacer()
            pasteButton
        }
    }

    var textField: some View {
        TextField(NSLocalizedString("enterDestinationTag", comment: ""), text: $destinationTag)
            .borderlessTextFieldStyle()
            .submitLabel(.next)
            .disableAutocorrection(true)
            .textFieldStyle(TappableTextFieldStyle())
            .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary)
    }

    var pasteButton: some View {
        Button {
            pasteDestinationTag()
        } label: {
            pasteLabel
        }
    }

    var pasteLabel: some View {
        Image(systemName: "square.on.square")
    }
}

#Preview {
    DestinationTagTextField(destinationTag: .constant(""))
}

#if os(iOS)
import SwiftUI

extension DestinationTagTextField {
    var container: some View {
        content
            .keyboardType(.numberPad)
    }

    func pasteDestinationTag() {
        if let clipboardContent = UIPasteboard.general.string {
            destinationTag = clipboardContent
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension DestinationTagTextField {
    var container: some View {
        content
    }

    func pasteDestinationTag() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            destinationTag = clipboardContent
        }
    }
}
#endif
