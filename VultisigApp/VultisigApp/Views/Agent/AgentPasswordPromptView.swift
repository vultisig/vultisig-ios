//
//  AgentPasswordPromptView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentPasswordPromptView: View {
    let onSubmit: (String) -> Void

    @State private var password = ""
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Theme.colors.bgPrimary.ignoresSafeArea()

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

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Theme.colors.bgSurface1)
                        .cornerRadius(12)
                        .foregroundColor(Theme.colors.textPrimary)
                        .padding(.horizontal)

                    Button {
                        isSubmitting = true
                        onSubmit(password)
                        dismiss()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Connect")
                                .font(.body.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            password.isEmpty
                                ? Theme.colors.bgButtonDisabled
                                : Theme.colors.bgButtonPrimary
                        )
                        .foregroundColor(
                            password.isEmpty
                                ? Theme.colors.textButtonDisabled
                                : Theme.colors.textButtonDark
                        )
                        .cornerRadius(12)
                    }
                    .disabled(password.isEmpty)
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.colors.textTertiary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AgentPasswordPromptView { password in
        print("Password: \(password)")
    }
}
