//
//  SendCryptoAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoAmountTextField: View {
    @Binding var amount: String

    /// Called synchronously on every keystroke, right after the field's source of
    /// truth is written.
    ///
    /// Debouncing is deliberately the owner's concern, not the field's. The
    /// pending commit has to be cancellable by whoever writes the amount *next* —
    /// a Max preset, a QR fill, a reset — and none of those go through this
    /// field. A debouncer scoped to the field (let alone a process-wide one)
    /// leaves them nothing to cancel, so a superseded keystroke still lands and
    /// undoes the newer write.
    var onChange: (String) -> Void
    var onMaxPressed: (() -> Void)?
    var font: Font = Theme.fonts.largeTitle
    /// Draws the digits in an overlay that rolls on change, while the field
    /// itself stays transparent and keeps input, caret and selection.
    var rendersAnimatedDigits = false

    @Environment(\.isEnabled) var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var placeholder: String { NSLocalizedString("0", comment: "").capitalized }

    var body: some View {
        textField
        #if os(iOS)
            .keyboardType(.decimalPad)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .textFieldStyle(TappableTextFieldStyle())
        #endif
    }

    /// Writes the field's source of truth and reports the keystroke, both
    /// synchronously. Shared by the text field and the max-length clamp so both
    /// go through one path.
    private var editedBinding: Binding<String> {
        Binding<String>(
            get: { amount },
            set: { newValue in
                guard amount != newValue else { return }
                amount = newValue
                onChange(newValue)
            }
        )
    }

    var textField: some View {
        TextField(Self.placeholder, text: editedBinding, prompt: prompt)
        .borderlessTextFieldStyle()
        .font(font)
        .disableAutocorrection(true)
        .textFieldStyle(TappableTextFieldStyle())
        .foregroundStyle(rendersAnimatedDigits ? .clear : textColor)
        .maxLength(editedBinding)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .overlay {
            if rendersAnimatedDigits {
                animatedDigits
            }
        }
    }

    private var textColor: Color {
        isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary
    }

    /// The overlay draws the placeholder too, so the field's own goes clear.
    private var prompt: Text? {
        rendersAnimatedDigits ? Text(Self.placeholder).foregroundStyle(.clear) : nil
    }

    private var animatedDigits: some View {
        Text(amount.isEmpty ? Self.placeholder : amount)
            .font(font)
            .foregroundStyle(amount.isEmpty ? Theme.colors.textTertiary : textColor)
            .lineLimit(1)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: amount)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    var maxButton: some View {
        Button { onMaxPressed?() } label: {
            Text(NSLocalizedString("max", comment: "").uppercased())
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }

    var showButton: Bool {
        return onMaxPressed != nil
    }
}

#Preview {
    SendCryptoAmountTextField(
        amount: .constant(.empty),
        onChange: { _ in },
        onMaxPressed: { }
    )
    .environmentObject(SettingsViewModel())
}
