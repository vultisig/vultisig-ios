//
//  AgentPasswordPromptView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vultisig", category: "AgentPasswordPrompt")

struct AgentPasswordPromptScreen: View {
    let usesFastVault: Bool
    let onSubmit: (String) async -> String?

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen(title: "") {
            ZStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.colors.turquoise)

                    Text(usesFastVault ? "agentEnterFastVaultPassword".localized : "agentEnterVaultPassword".localized)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(promptDescription)
                        .font(.subheadline)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    CommonTextField(
                        text: $password,
                        placeholder: usesFastVault ? "agentFastVaultPasswordPlaceholder".localized : "password".localized,
                        isSecure: .constant(true),
                        error: $errorMessage
                    )
                    .padding(.horizontal)

                    PrimaryButton(
                        title: "agentConnect".localized,
                        isLoading: isSubmitting
                    ) {
                        Task {
                            isSubmitting = true
                            errorMessage = nil
                            let submitError = await onSubmit(password)
                            isSubmitting = false

                            if let submitError {
                                errorMessage = submitError
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(password.isEmpty)
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel".localized) { dismiss() }
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("cancel".localized) { dismiss() }
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                #endif
            }
        }
        .presentationDetents([.medium])
        .onChange(of: password) { _, _ in
            errorMessage = nil
        }
    }

    private var promptDescription: String {
        if usesFastVault {
            return "agentFastVaultPasswordDescription".localized
        }

        return "agentPasswordDescription".localized
    }
}

#Preview {
    AgentPasswordPromptScreen(usesFastVault: true) { _ in
        logger.debug("Password submitted")
        return nil
    }
}
