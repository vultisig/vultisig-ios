//
//  AgentPasswordPromptView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentPasswordPromptScreen: View {
    let onSubmit: (String) -> Void

    @State private var password = ""
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen(title: "") {
            ZStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.colors.turquoise)

                    Text("Enter Vault Password")
                        .font(.title3.bold())
                        .foregroundColor(Theme.colors.textPrimary)

                    Text("Your password is needed to sign into the agent service using your vault.")
                        .font(.subheadline)
                        .foregroundColor(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    CommonTextField(
                        text: $password,
                        placeholder: "Password",
                        isSecure: .constant(true)
                    )
                    .padding(.horizontal)

                    PrimaryButton(
                        title: "Connect",
                        isLoading: isSubmitting
                    ) {
                        isSubmitting = true
                        onSubmit(password)
                        dismiss()
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
                        .foregroundColor(Theme.colors.textTertiary)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.colors.textTertiary)
                }
                #endif
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AgentPasswordPromptScreen { password in
        print("Password: \(password)")
    }
}
