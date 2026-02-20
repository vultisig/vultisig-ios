//
//  ReferralCodeSheet.swift
//  VultisigApp
//
//  Created on 20/02/2026.
//

import SwiftUI

struct ReferralCodeSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: VaultSetupViewModel

    @State private var referralInput: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var isValid: Bool?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("referralCodeTitle".localized)
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
                    description
                }
                textField
                applyButton
                Spacer()
            }
            .padding(.horizontal, 24)
            .crossPlatformToolbar(showsBackButton: false) {
                CustomToolbarItem(placement: .trailing) {
                    ToolbarButton(image: "x") {
                        isPresented.toggle()
                    }
                    .supportsLiquidGlass { view, isSupported in
                        view.padding(.top, isSupported ? 0 : 16)
                    }
                }
            }
        }
        .onAppear {
            referralInput = viewModel.referralField.value
            if viewModel.referralField.valid {
                isValid = true
            }
        }
    }

    // MARK: - Description

    private var description: some View {
        let text = descriptionAttributedString
        return Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionAttributedString: AttributedString {
        var base = AttributedString("referralCodeDescription".localized + " ")
        base.font = Theme.fonts.bodySMedium
        base.foregroundColor = Theme.colors.textTertiary

        var highlight = AttributedString("referralCodeDescriptionHighlight".localized)
        highlight.font = Theme.fonts.bodySMedium
        highlight.foregroundColor = Theme.colors.textPrimary

        return base + highlight
    }

    // MARK: - Text Field

    private var textField: some View {
        CommonTextField(
            text: $referralInput,
            placeholder: "enter4DigitCode".localized,
            error: $error,
            isValid: $isValid
        )
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        PrimaryButton(
            title: "applyReferral".localized,
            isLoading: isLoading
        ) {
            applyReferral()
        }
        .disabled(isLoading)
    }

    // MARK: - Actions

    private func applyReferral() {
        let trimmed = referralInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            viewModel.clearReferral()
            isPresented = false
            return
        }

        guard trimmed.count <= 4 else {
            error = "referralLaunchCodeLengthError".localized
            isValid = false
            return
        }

        isLoading = true
        error = nil
        isValid = nil

        Task { @MainActor in
            defer { isLoading = false }
            do {
                try await ReferredCodeInteractor().verify(code: trimmed)
                viewModel.referralField.value = trimmed
                viewModel.setReferralError(nil)
                isPresented = false
            } catch {
                self.error = error.localizedDescription
                self.isValid = false
            }
        }
    }
}
