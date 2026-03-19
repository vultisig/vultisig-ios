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

    var body: some View {
        VStack(spacing: 24) {
            Text("enableBiometricsFastSigning".localized)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)

            GradientListSeparator()

            SecureTextField(
                value: $viewModel.password,
                placeholder: "enterPassword".localized,
                error: $viewModel.passwordError
            )

            PrimaryButton(title: "enable".localized) {
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
        }
        .onChange(of: viewModel.password) { _, _ in
            viewModel.passwordError = nil
        }
        .onAppear { viewModel.resetData() }
        .interactiveDismissDisabled(viewModel.isLoading)
    }
}
