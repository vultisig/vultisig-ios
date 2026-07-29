//
//  PasscodeEntryView.swift
//  VultisigApp
//

import SwiftUI

/// Five-digit entry: filled dots plus a keypad on iOS, hardware keyboard on macOS.
///
/// One component for every flow — lock screen, set, confirm, change, disable — so
/// entering a passcode looks and behaves the same everywhere it is asked for.
struct PasscodeEntryView: View {

    let title: String
    let subtitle: String?
    var errorMessage: String?
    var isBusy: Bool = false
    @Binding var passcode: String
    #if os(macOS)
    @FocusState private var isFieldFocused: Bool
    #endif
    /// Called once the last digit lands, so no flow needs its own submit button.
    let onComplete: (String) -> Void

    private var digitCount: Int { PasscodeService.passcodeLength }

    var body: some View {
        VStack(spacing: 32) {
            header
            dots
            message
            Spacer()
            keypad
        }
        .frame(maxWidth: .infinity)
        .onChange(of: passcode) { _, value in
            guard value.count == digitCount else { return }
            onComplete(value)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var dots: some View {
        HStack(spacing: 16) {
            ForEach(0..<digitCount, id: \.self) { index in
                Circle()
                    .fill(index < passcode.count ? Theme.colors.primaryAccent4 : Theme.colors.bgSurface2)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().stroke(
                            errorMessage == nil ? Theme.colors.borderLight : Theme.colors.alertError,
                            lineWidth: 1
                        )
                    )
            }
        }
        .accessibilityIdentifier(AccessibilityID.Passcode.dots)
        .accessibilityValue("\(passcode.count)")
    }

    @ViewBuilder
    private var message: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.alertError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        } else {
            // Reserved so the dots do not jump when an error appears.
            Text(" ")
                .font(Theme.fonts.caption12)
        }
    }

    private func append(_ digit: String) {
        guard passcode.count < digitCount, !isBusy else { return }
        passcode.append(digit)
    }

    private func deleteLast() {
        guard !passcode.isEmpty, !isBusy else { return }
        passcode.removeLast()
    }
}

#if os(iOS)
extension PasscodeEntryView {

    private var keypadRows: [[String]] {
        [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
    }

    var keypad: some View {
        VStack(spacing: 12) {
            ForEach(keypadRows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        keyView(for: key)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .disabled(isBusy)
    }

    @ViewBuilder
    private func keyView(for key: String) -> some View {
        switch key {
        case "":
            Color.clear.frame(maxWidth: .infinity, minHeight: 64)
        case "⌫":
            Button(action: deleteLast) {
                Image(systemName: "delete.left")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .accessibilityIdentifier(AccessibilityID.Passcode.deleteKey)
            .accessibilityLabel("delete".localized)
        default:
            Button {
                append(key)
            } label: {
                Text(key)
                    .font(Theme.fonts.title1)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.colors.bgSurface1)
                    .cornerRadius(16)
            }
            .accessibilityIdentifier(AccessibilityID.Passcode.digitKey(key))
        }
    }
}
#endif

#if os(macOS)
extension PasscodeEntryView {

    /// No on-screen keypad on macOS — the hardware keyboard drives entry and the
    /// dots above render the state.
    ///
    /// The field is visible and focused on appearance rather than hidden at one
    /// pixel: an invisible field gives the user nothing to click when focus is
    /// lost, which makes entry unreliable and occasionally impossible.
    var keypad: some View {
        SecureField("passcodeEnterTitle".localized, text: Binding(
            get: { passcode },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                passcode = String(digits.prefix(PasscodeService.passcodeLength))
            }
        ))
        .textFieldStyle(.roundedBorder)
        .font(Theme.fonts.bodyMMedium)
        .frame(maxWidth: 220)
        .padding(.bottom, 24)
        .focused($isFieldFocused)
        .disabled(isBusy)
        .onAppear { isFieldFocused = true }
        .accessibilityIdentifier(AccessibilityID.Passcode.macField)
    }
}
#endif
