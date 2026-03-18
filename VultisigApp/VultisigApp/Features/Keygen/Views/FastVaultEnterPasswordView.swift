//
//  FastVaultEnterPasswordView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 12.09.2024.
//

import SwiftUI

struct FastVaultEnterPasswordView: View {
    @AppStorage("isBiometryEnabled") var isBiometryEnabled: Bool = true

    @State var isLoading: Bool = false
    @State var errorMessage: String? = nil
    @State var showHint: Bool = false

    @Binding var password: String

    @Environment(\.dismiss) var dismiss

    let vault: Vault
    let onSubmit: (() -> Void)?

    private let keychain = DefaultKeychainService.shared
    private let biometryService = BiometryService.shared

    var hint: String? {
        keychain.getFastHint(pubKeyECDSA: vault.pubKeyECDSA)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Icon
            Icon(
                named: "focus-lock",
                color: Theme.colors.primaryAccent4,
                size: 32
            )
            .padding(.top, 32)

            // Title
            Text("enterYourPassword".localized)
                .font(Theme.fonts.title2)
                .foregroundColor(Theme.colors.textPrimary)
                .padding(.vertical, 10)

            // Password field
            SecureTextField(
                value: $password,
                placeholder: "enterPassword".localized,
                error: $errorMessage
            )

            // Show hint toggle
            if let hint, hint.isNotEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHint.toggle()
                    }
                }, label: {
                    HStack(spacing: 4) {
                        Text("showHint".localized)
                            .font(Theme.fonts.caption12)
                            .foregroundColor(Theme.colors.textTertiary)

                        Icon(named: "chevron-down", color: Theme.colors.textTertiary, size: 16)
                            .rotationEffect(.degrees(showHint ? 180 : 0))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                       )
                .buttonStyle(.plain)

                // Hint text
                Text(hint)
                    .font(.system(size: 12, weight: .medium).italic())
                    .foregroundColor(Theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showHint ? 1 : 0)
            }

            Spacer()

            // Next button
            PrimaryButton(title: "next".localized) {
                Task {
                    await checkPassword()
                }
            }
            .disabled(password.isEmpty || isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Theme.colors.bgPrimary)
#if os(iOS)
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(hint == nil ? 300 : 330)])
        .presentationBackground(Theme.colors.bgPrimary)
#else
        .overlay(
            ToolbarButton(image: "x", action: { dismiss() })
                .padding(.top, 16)
                .padding(.trailing, 16),
            alignment: .topTrailing
        )
#endif
        .onAppear {
            tryAuthenticate()
        }

    }

    @MainActor func checkPassword() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let isValidPassword = await FastVaultService.shared.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: password
        )

        if isValidPassword {
            savePassword()
            onSubmit?()
            dismiss()
        } else {
            errorMessage = NSLocalizedString("incorrectPasswordTryAgain", comment: "")
        }
    }

    func savePassword() {
        keychain.setFastPassword(password, pubKeyECDSA: vault.pubKeyECDSA)
    }

    func tryAuthenticate() {
        guard let fastPassword = keychain.getFastPassword(pubKeyECDSA: vault.pubKeyECDSA) else {
            return
        }

        guard !fastPassword.isEmpty, isBiometryEnabled else {
            return
        }

        biometryService.authenticate(
            reason: "Authenticate to fill FastServer password",
            onSuccess: {
                password = fastPassword
                onSubmit?()
                dismiss()
            },
            onError: { error in
                // Log authentication error - don't fail silently
                print("Fast Vault authentication error: \(error.localizedDescription)")
                // Error is shown by system dialog, no need to show another alert
            })
    }
}
