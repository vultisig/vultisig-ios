//
//  FastSigningPasswordSheetView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/09/2025.
//

import SwiftUI

struct FastSigningPasswordSheetView: View, BottomSheetProperties {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SettingsBiometryViewModel
    let vault: Vault

    var bgColor: Color? { Theme.colors.bgPrimary }
    var usesSystemGrabber: Bool { true }

    /// The field puts its error 4pt below it, 12pt closer than this stack's spacing.
    private static let errorSpacingOverlap: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("biometricsFastSigning".localized)
                .settingsText(.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            SecureTextField(
                value: $viewModel.password,
                placeholder: "settingsEnterPassword".localized,
                error: $viewModel.passwordError,
                appearance: .settingsInput
            )

            PrimaryButton(title: "enable", size: .compact) {
                Task {
                    let isValid = await viewModel.validateForm(vault: vault)

                    if isValid {
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
            }
            .disabled(!viewModel.isSaveEnabled)

            // The sheet measures itself once with no error, so this holds the error's height.
            if viewModel.passwordError == nil {
                Text("wrongVaultPassword".localized)
                    .font(Theme.fonts.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -Self.errorSpacingOverlap)
                    .hidden()
            }
        }
        .onChange(of: viewModel.password) { _, _ in
            viewModel.passwordError = nil
        }
        .onAppear { viewModel.resetData() }
        .interactiveDismissDisabled(viewModel.isLoading)
    }
}
