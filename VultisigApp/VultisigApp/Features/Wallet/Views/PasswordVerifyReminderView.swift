//
//  PasswordVerifyReminderView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-25.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "password-verify-reminder")

struct PasswordVerifyReminderView: View {
    let vault: Vault
    @Binding var isSheetPresented: Bool

    @AppStorage("biweeklyPasswordVerifyDate") private var biweeklyPasswordVerifyDate: Double?

    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isHintVisible = false

    private let fastVaultService: FastVaultService = .shared
    private let keychain = DefaultKeychainService.shared

    private var hint: String? {
        keychain.getFastHint(pubKeyECDSA: vault.pubKeyECDSA)
    }

    var body: some View {
        VStack(spacing: 16) {
            Icon(
                named: "focus-lock",
                color: Theme.colors.primaryAccent4,
                size: 32
            )
            .padding(.top, 24)

            VStack(spacing: 12) {
                Text("verifyYourPasswordFor".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(vault.name)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .multilineTextAlignment(.center)

            Text("verifyPasswordPeriodicReminder".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SecureTextField(
                value: $password,
                placeholder: "enterPassword".localized,
                error: $errorMessage
            )
            .padding(.top, 4)

            if let hint, !hint.isEmpty {
                hintSection(hint: hint)
            }

            Spacer(minLength: 0)

            PrimaryButton(title: "done".localized) {
                Task { await verifyPassword() }
            }
            .disabled(password.isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.colors.bgPrimary)
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .onDisappear(perform: resetVerificationTimer)
    }

    private func hintSection(hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHintVisible.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("showHint".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)

                    Icon(
                        named: "chevron-down",
                        color: Theme.colors.textTertiary,
                        size: 16
                    )
                    .rotationEffect(.degrees(isHintVisible ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            Text(hint)
                .font(Theme.fonts.caption12.italic())
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isHintVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView().preferredColorScheme(.dark)
        }
    }

    private func verifyPassword() async {
        guard !password.isEmpty else {
            errorMessage = "emptyField".localized
            return
        }

        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let isValid = await fastVaultService.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: password
        )

        if isValid {
            logger.info("Password verification succeeded")
            isSheetPresented = false
        } else {
            errorMessage = "incorrectPasswordTryAgain".localized
        }
    }

    private func resetVerificationTimer() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        biweeklyPasswordVerifyDate = startOfToday.timeIntervalSince1970
    }
}
