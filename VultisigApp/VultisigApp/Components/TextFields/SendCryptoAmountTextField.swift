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

    @Environment(\.isEnabled) var isEnabled

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
        TextField(NSLocalizedString("0", comment: "").capitalized, text: editedBinding)
        .borderlessTextFieldStyle()
        .font(Theme.fonts.largeTitle)
        .disableAutocorrection(true)
        .textFieldStyle(TappableTextFieldStyle())
        .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary)
        .maxLength(editedBinding)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
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
