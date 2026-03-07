//
//  AgentPasswordPromptView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

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

                    Text(usesFastVault ? "Enter Fast Vault Password" : "Enter Vault Password")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(promptDescription)
                        .font(.subheadline)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    CommonTextField(
                        text: $password,
                        placeholder: usesFastVault ? "Fast Vault Password" : "Password",
                        isSecure: .constant(true),
                        error: $errorMessage
                    )
                    .padding(.horizontal)

                    PrimaryButton(
                        title: "Connect",
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
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { dismiss() }
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
            return "Your Fast Vault password is needed to sign into the agent service using your vault."
        }

        return "Your password is needed to sign into the agent service using your vault."
    }
}

#Preview {
    AgentPasswordPromptScreen(usesFastVault: true) { password in
        print("Password: \(password)")
        return nil
    }
}
