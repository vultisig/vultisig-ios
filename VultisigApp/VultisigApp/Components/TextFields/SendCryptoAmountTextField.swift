//
//  SendCryptoAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoAmountTextField: View {
    @Binding var amount: String

    /// Called synchronously on every keystroke, before the debounce is armed,
    /// so the owner can record the edit and hand back a token identifying it.
    /// The debounced `onChange` presents that token back, letting the owner drop
    /// a callback that a newer edit or a programmatic fill has since superseded.
    ///
    /// `DebounceHelper.shared` is process-wide and holds a single pending work
    /// item, so a callback armed by typing can outlive the value that armed it —
    /// long enough to land after a Max preset has replaced the amount.
    var beginEdit: () -> Int = { 0 }
    var onChange: (String, Int) async -> Void
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

    /// Writes the field's source of truth synchronously, then arms the debounced
    /// commit with the token `beginEdit` minted for this keystroke. Shared by the
    /// text field and the max-length clamp so both go through one debounce path.
    private var debouncedBinding: Binding<String> {
        Binding<String>(
            get: { amount },
            set: { newValue in
                guard amount != newValue else { return }
                amount = newValue

                let generation = beginEdit()
                DebounceHelper.shared.debounce {
                    Task { await onChange(newValue, generation) }
                }
            }
        )
    }

    var textField: some View {
        TextField(NSLocalizedString("0", comment: "").capitalized, text: debouncedBinding)
        .borderlessTextFieldStyle()
        .font(Theme.fonts.largeTitle)
        .disableAutocorrection(true)
        .textFieldStyle(TappableTextFieldStyle())
        .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textSecondary)
        .maxLength(debouncedBinding)
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
        onChange: { _, _ in },
        onMaxPressed: { }
    )
    .environmentObject(SettingsViewModel())
}
