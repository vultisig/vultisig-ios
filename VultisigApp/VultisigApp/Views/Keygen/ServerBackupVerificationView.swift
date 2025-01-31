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
    let vault: Vault
    let selectedTab: SetupVaultState?
    @ObservedObject var viewModel: KeygenViewModel
    
    @State var verificationCode = ""
    
    @State var isLoading: Bool = false
    @State var isNavigationActive: Bool = false
    
    @State var alertDescription = "verificationCodeTryAgain"
    @State var showAlert: Bool = false
    @State var showHomeView: Bool = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let animationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    
    var body: some View {
        ZStack {
            Background()
            container
        }
        .navigationDestination(isPresented: $isNavigationActive) {
            if showHomeView {
                HomeView()
            } else {
                BackupVaultNowView(vault: vault)
            }
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("enter5DigitVerificationCode", comment: ""))
            .font(.body34BrockmannMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.leading)
    }
    
    var description: some View {
        Text(NSLocalizedString("enter5DigitVerificationCodeDescription", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var textField: some View {
        HStack {
            field
            pasteButton
        }
        .colorScheme(.dark)
        .padding(.top, 32)
    }
    
    var field: some View {
        TextField(NSLocalizedString("enterCode", comment: "").capitalized, text: $verificationCode)
            .foregroundColor(.neutral0)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .font(.body16BrockmannMedium)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(getBorderColor(), lineWidth: 1)
            )
    }
    
    var pasteButton: some View {
        Button {
            pasteCode()
        } label: {
            Text(NSLocalizedString("paste", comment: ""))
                .padding(12)
                .frame(height: 56)
                .font(.body16BrockmannMedium)
                .foregroundColor(.neutral0)
                .background(Color.blue600)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue200, lineWidth: 1)
                )
        }
    }
    
    var loadingText: some View {
        HStack {
            animationVM.view()
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
    
    var buttons: some View {
        VStack(spacing: 12) {
            verifyButton
            cancelButton
        }
    }
    
    var verifyButton: some View {
        Button {
            verifyCode()
        } label: {
            FilledButton(
                title: isLoading ? "verifying..." : "next",
                textColor: isLoading ? .textDisabled : .blue600,
                background: isLoading ? .buttonDisabled : .turquoise600
            )
        }
    }
    
    var cancelButton: some View {
        Button {
            deleteVault()
        } label: {
            OutlineButton(title: "cancel", gradient: LinearGradient.cancelRed)
        }
        .padding(.bottom, 30)
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
            
            (isNavigationActive, showAlert) = await FastVaultService.shared.verifyBackupOTP(
                ecdsaKey: vault.pubKeyECDSA,
                OTPCode: verificationCode
            )
            
            isLoading = false
        }
    }
    
    private func deleteVault() {
        modelContext.delete(vault)
        isLoading = true
        
        do {
            try modelContext.save()
            isLoading = false
            showHomeView = true
            isNavigationActive = true
        } catch {
            print("Error: \(error)")
        }
    }
    
    func getBorderColor() -> Color {
        if showAlert {
            return .alertRed
        } else {
            return .blue200
        }
    }
}

#Preview {
    ServerBackupVerificationView(vault: Vault.example, selectedTab: .secure, viewModel: KeygenViewModel())
}
