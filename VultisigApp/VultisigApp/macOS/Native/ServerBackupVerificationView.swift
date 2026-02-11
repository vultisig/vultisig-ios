//
//  ServerBackupVerificationScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

import SwiftUI
import SwiftData
import RiveRuntime

struct ServerBackupVerificationScreen: View {
    let tssType: TssType
    let vault: Vault
    let email: String

    @Binding var isPresented: Bool
    @Binding var tabIndex: Int
    let onBackup: () -> Void
    let onBackToEmailSetup: () -> Void

    @FocusState var focusedField: Int?

    @State var otp: [String] = Array(repeating: "", count: codeLength)
    @State var isLoading: Bool = false
    @State var showAlert: Bool = false
    @State var alertDescription = "incorrectCodeTryAgain"
    @State var animationVM: RiveViewModel?

    @Environment(\.modelContext) private var modelContext

    static var codeLength: Int { 4 }

    var verificationCode: String {
        otp.joined().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Body

    var body: some View {
        Screen(showNavigationBar: false) {
            VStack(spacing: 32) {
                VaultSetupStepIcon(state: .active, icon: "email-circle")
                    .padding(.top, 56)

                VStack(spacing: 16) {
                    titleView
                    subtitleView
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    otpField
                    statusView
                }
                
                Spacer()

                footerView
                    .padding(.bottom, 32)
                    .opacity(isLoading ? 0 : 1)
                    .animation(.easeInOut, value: isLoading)
            }
        }
        .applySheetSize()
        .sheetStyle()
        .onAppear {
            focusedField = 0
            animationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        }
        .onDisappear {
            animationVM?.stop()
        }
        .animation(.easeInOut, value: showAlert)
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var titleView: some View {
        Text("enter5DigitVerificationCode".localized)
            .font(Theme.fonts.title2)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 243)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitleView: some View {
        Text("enter5DigitVerificationCodeDescription".localized)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textTertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: - OTP Field

    private var otpField: some View {
        HStack(spacing: 8) {
            digitFields
            pasteButton
        }
    }

    private var digitFields: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.codeLength, id: \.self) { index in
                digitInput(index: index)
            }
        }
    }

    private func digitInput(index: Int) -> some View {
        digitTextField(index: index)
            .font(Theme.fonts.title1)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .disableAutocorrection(true)
            .frame(width: 58, height: 46)
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(digitBorderColor(index), lineWidth: 1.5)
            )
            .focused($focusedField, equals: index)
            .onChange(of: otp[index]) { _, newValue in
                handleInputChange(newValue, index: index)
            }
    }

    @ViewBuilder
    private func digitTextField(index: Int) -> some View {
        #if os(iOS)
        OTPCharTextField(text: $otp[index]) {
            focusedField = max(0, index - 1)
        }
        .keyboardType(.numberPad)
        #else
        BackspaceDetectingTextField(text: $otp[index]) {
            handleBackspaceTap(index: index)
        }
        .borderlessTextFieldStyle()
        #endif
    }

    private func digitBorderColor(_ index: Int) -> Color {
        if showAlert {
            return Theme.colors.alertError
        }
        return focusedField == index ? Theme.colors.border : Theme.colors.bgSurface2
    }

    private var pasteButton: some View {
        Button {
            pasteCode()
        } label: {
            Text("paste".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(height: 46)
                .frame(maxWidth: 76)
                .background(Theme.colors.bgSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Theme.colors.borderExtraLight.opacity(0.03), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        if isLoading {
            HStack(spacing: 8) {
                animationVM?.view()
                    .frame(width: 24, height: 24)

                Text("verifyingCodePleaseWait".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
            }
        } else if showAlert {
            Text(alertDescription.localized)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Theme.colors.alertError)
                .font(Theme.fonts.bodySMedium)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 12) {
            Text(String(format: "emailSentTo".localized, email))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            Button {
                deleteVault()
            } label: {
                Text("useDifferentEmail".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.colors.bgSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.colors.borderExtraLight.opacity(0.03), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    func handleInputChange(_ newValue: String, index: Int) {
        if newValue.count == Self.codeLength {
            pasteCode()
        }

        if !newValue.isEmpty && index < Self.codeLength - 1 {
            focusedField = index + 1
        } else if newValue.isEmpty && index > 0 {
            focusedField = index - 1
        }

        if verificationCode.count == Self.codeLength {
            verifyCode()
        }
    }

    func pasteCode() {
        #if os(iOS)
        guard
            let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
            raw.count == Self.codeLength,
            raw.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
        else { return }

        otp = raw.map(String.init)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = Self.codeLength - 1
        }
        #else
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string),
           clipboardContent.count == Self.codeLength {
            otp = clipboardContent.map { String($0) }
        }
        #endif
    }

    #if os(macOS)
    private func handleBackspaceTap(index: Int) {
        if otp[index].isEmpty && index > 0 {
            otp[index] = ""
            focusedField = index - 1
        }
    }
    #endif

    private func verifyCode() {
        guard !verificationCode.isEmpty else {
            alertDescription = "emptyField"
            showAlert = true
            return
        }

        Task {
            alertDescription = "incorrectCodeTryAgain"
            isLoading = true

            let isSuccess = await FastVaultService.shared.verifyBackupOTP(
                ecdsaKey: vault.pubKeyECDSA,
                OTPCode: verificationCode
            )

            if isSuccess {
                tabIndex = 3
                isPresented = false

                if tssType == .Migrate {
                    onBackup()
                }
            } else {
                showAlert = true
            }

            isLoading = false
        }
    }

    private func deleteVault() {
        modelContext.delete(vault)
        isLoading = true

        do {
            try modelContext.save()
            isLoading = false
            isPresented = false
            onBackToEmailSetup()
        } catch {
            print("Error: \(error)")
        }
    }
}

#Preview {
    ServerBackupVerificationScreen(
        tssType: .Keygen,
        vault: Vault.example,
        email: "mail@email.com",
        isPresented: .constant(false),
        tabIndex: .constant(2),
        onBackup: {},
        onBackToEmailSetup: {}
    )
}
