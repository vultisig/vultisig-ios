//
//  AgentApproveTransactionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/03/2026.
//

import SwiftUI

struct AgentApproveTransactionView: View {
    @AppStorage("isBiometryEnabled") var isBiometryEnabled: Bool = true

    @Binding var password: String

    let vault: Vault
    let onSubmit: (() -> Void)?

    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let keychain = DefaultKeychainService.shared
    private let biometryService = BiometryService.shared

    var body: some View {
        VStack(spacing: 16) {
            header

            Spacer()

            passwordField

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertError)
            }

            if isBiometryEnabled, keychain.getFastPassword(pubKeyECDSA: vault.pubKeyECDSA) != nil {
                Button {
                    tryBiometricAuth()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(Theme.fonts.bodyMMedium)
                        Text("agentConfirmFaceID".localized)
                            .font(Theme.fonts.bodySMedium)
                    }
                    .foregroundStyle(Theme.colors.turquoise)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Theme.colors.bgPrimary)
        #if os(iOS)
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(300)])
        .presentationBackground(Theme.colors.bgPrimary)
        #endif
        .onAppear {
            tryBiometricAuth()
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("agentApproveTransaction".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.turquoise)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Theme.colors.bgSurface1)
                        .clipShape(Circle())
                }
                Spacer()
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Password Field

    private var passwordField: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            SecureField("agentEnterVaultPasswordPlaceholder".localized, text: $password)
                .textFieldStyle(.plain)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Button {
                submitPassword()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(
                        password.isEmpty
                        ? Theme.colors.textTertiary
                        : Theme.colors.turquoise
                    )
            }
            .disabled(password.isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(24)
    }

    // MARK: - Actions

    private func submitPassword() {
        Task {
            await checkPassword()
        }
    }

    @MainActor
    private func checkPassword() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let isValidPassword = await FastVaultService.shared.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: password
        )

        if isValidPassword {
            keychain.setFastPassword(password, pubKeyECDSA: vault.pubKeyECDSA)
            onSubmit?()
            dismiss()
        } else {
            errorMessage = "incorrectPasswordTryAgain".localized
        }
    }

    private func tryBiometricAuth() {
        guard let fastPassword = keychain.getFastPassword(pubKeyECDSA: vault.pubKeyECDSA),
              !fastPassword.isEmpty,
              isBiometryEnabled else {
            return
        }

        biometryService.authenticate(
            reason: "Authenticate to approve transaction",
            onSuccess: {
                password = fastPassword
                onSubmit?()
                dismiss()
            },
            onError: { _ in }
        )
    }
}

#Preview {
    AgentApproveTransactionView(
        password: .constant(""),
        vault: Vault(name: "Test"),
        onSubmit: nil
    )
}
