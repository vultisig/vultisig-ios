//
//  ServerBackupVerificationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

import SwiftUI
import SwiftData
import RiveRuntime

struct ServerBackupVerificationView: View {
    let tssType: TssType
    let vault: Vault
    let email: String

    @Binding var isPresented: Bool
    @Binding var isBackupLinkActive: Bool
    @Binding var tabIndex: Int
    @Binding var goBackToEmailSetup: Bool

    @FocusState var focusedField: Int?

    @State var otp: [String] = Array(repeating: "", count: codeLength)

    @State var isLoading: Bool = false

    @State var alertDescription = "verificationCodeTryAgain"
    @State var showAlert: Bool = false
    @State var animationVM: RiveViewModel? = nil

    @Environment(\.modelContext) private var modelContext

    static var codeLength: Int {
        return 4
    }

    var verificationCode: String {
        return otp.joined().trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        ZStack {
            Background()
            container
        }
        .onAppear {
            focusedField = 0
            animationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        }
        .safeAreaInset(edge: .bottom) {
            cancelButton
        }
        .animation(.easeInOut, value: showAlert)
        .onDisappear {
            animationVM?.stop()
        }
        .interactiveDismissDisabled()
    }
    
    var title: some View {
        Text(NSLocalizedString("enter5DigitVerificationCode", comment: ""))
            .font(.body34BrockmannMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.leading)
            .padding(.top, 50)
    }
    
    var description: some View {
        Text(NSLocalizedString("enter5DigitVerificationCodeDescription", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }

    private var cancelButton: some View {
        Button {
            deleteVault()
        } label: {
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("emailSentTo", comment: ""), email))
                    .font(.body14BrockmannMedium)
                    .foregroundColor(.extraLightGray)

                Text(NSLocalizedString("changeEmailAndRestart", comment: ""))
                    .font(.body14BrockmannMedium)
                    .foregroundColor(.lightText)
                    .underline()
            }
        }
        .padding(.bottom, 24)
        .buttonStyle(.plain)
    }

    func handleInputChange(_ oldValue: String, _ newValue: String, index: Int) {
        if newValue.count == Self.codeLength {
            pasteCode()
        }

        if !newValue.isEmpty && index < Self.codeLength - 1 {
            focusedField = index + 1
        } else if newValue.isEmpty && index > 0 {
            focusedField = index - 1
        }

        if verificationCode.count == Self.codeLength {
            focusedField = Self.codeLength - 1
            verifyCode()
        }
    }

    func getBorderColor(_ index: Int) -> Color {
        if showAlert {
            return .alertRed
        } else {
            return focusedField == index ? .blue200 : .blue400
        }
    }

    var pasteButton: some View {
        Button {
            pasteCode()
        } label: {
            Text(NSLocalizedString("paste", comment: ""))
                .padding(12)
                .frame(height: 46)
                .font(.body16BrockmannMedium)
                .foregroundColor(.neutral0)
                .background(Color.blue600)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue200, lineWidth: 1)
                )
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var loadingText: some View {
        HStack {
            animationVM?.view()
                .frame(width: 24, height: 24)
            
            Text(NSLocalizedString("verifyingCodePleaseWait", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body14BrockmannMedium)
            
            Spacer()
        }
    }
    
    var alertText: some View {
        Text(NSLocalizedString(alertDescription, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.alertRed)
            .font(.body14BrockmannMedium)
    }
    
    private func verifyCode() {
        guard !verificationCode.isEmpty else {
            alertDescription = "emptyField"
            showAlert = true
            return
        }
        
        Task {
            alertDescription = "verificationCodeTryAgain"
            isLoading = true
            
            let isSuccess = await FastVaultService.shared.verifyBackupOTP(
                ecdsaKey: vault.pubKeyECDSA,
                OTPCode: verificationCode
            )

            if isSuccess {
                tabIndex = 3
                isPresented = false
                
                if tssType == .Migrate {
                    isBackupLinkActive = true
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
            goBackToEmailSetup = true
        } catch {
            print("Error: \(error)")
        }
    }
}

#Preview {
    ServerBackupVerificationView(
        tssType: .Keygen,
        vault: Vault.example,
        email: "mail@email.com",
        isPresented: .constant(false),
        isBackupLinkActive: .constant(false),
        tabIndex: .constant(2),
        goBackToEmailSetup: .constant(false)
    )
}
