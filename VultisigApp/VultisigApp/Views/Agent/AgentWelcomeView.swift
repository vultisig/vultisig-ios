//
//  AgentWelcomeView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/03/2026.
//

import SwiftUI

struct AgentWelcomeView: View {
    let onAuthorize: (String) async -> String?

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            inlineHeader

            Separator(color: Theme.colors.borderLight, opacity: 1)

            VStack(spacing: 24) {
                Spacer()

                AgentOrbView(size: 80, animated: true)

                Text("agentWelcomeTitle".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("agentWelcomeSubtitle".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                Button {
                    submitPassword()
                } label: {
                    Text("agentAuthorizeAgent".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.turquoise)
                }

                CommonTextField(
                    text: $password,
                    placeholder: "agentFastVaultPasswordPlaceholder".localized,
                    isSecure: .constant(true),
                    error: $errorMessage
                )
                .padding(.horizontal, 16)
                .onSubmit {
                    submitPassword()
                }

                if isSubmitting {
                    ProgressView()
                        .tint(Theme.colors.turquoise)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        .onChange(of: password) { _, _ in
            errorMessage = nil
        }
    }

    // MARK: - Header

    private var inlineHeader: some View {
        ZStack {
            Text("Vultisig")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }

                Spacer()

                Button {
                    // Options menu placeholder
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgPrimary)
    }

    // MARK: - Actions

    private func submitPassword() {
        let text = password.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSubmitting else { return }

        Task {
            isSubmitting = true
            errorMessage = nil
            let submitError = await onAuthorize(text)
            isSubmitting = false

            if let submitError {
                errorMessage = submitError
            }
        }
    }
}

#Preview {
    AgentWelcomeView { _ in
        return nil
    }
}
