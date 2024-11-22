//
//  ServerBackupVerificationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

import SwiftUI

struct ServerBackupVerificationView: View {
    let vault: Vault
    @ObservedObject var viewModel: KeygenViewModel
    
    @State var verificationCode = ""
    
    @State var isLoading: Bool = false
    @State var isNavigationActive: Bool = false
    
    @State var alertTitle = "incorrectCode"
    @State var alertDescription = "verificationCodeTryAgain"
    @State var showAlert: Bool = false
    
    var body: some View {
        ZStack {
            Background()
            container
            
            if isLoading {
                loader
            }
        }
        .navigationDestination(isPresented: $isNavigationActive) {
            BackupVaultNowView(vault: vault)
        }
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("enterBackupVerificationCode", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
            .multilineTextAlignment(.leading)
            .padding(.top, 30)
    }
    
    var textField: some View {
        TextField(NSLocalizedString("enterCode", comment: "").capitalized, text: $verificationCode)
            .foregroundColor(.neutral0)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .font(.body12MenloBold)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.blue600)
            .cornerRadius(10)
            .colorScheme(.dark)
    }
    
    var disclaimer: some View {
        OutlinedDisclaimer(text: NSLocalizedString("serverBackupVerificationDisclaimer", comment: ""))
            .padding(.bottom, 18)
    }
    
    var button: some View {
        Button {
            verifyCode()
        } label: {
            FilledButton(title: "continue")
        }
        .padding(.bottom, 30)
        .grayscale(verificationCode.isEmpty ? 1 : 0)
        .disabled(verificationCode.isEmpty)
    }
    
    var loader: some View {
        Loader()
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(alertTitle, comment: "")),
            message: Text(NSLocalizedString(alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func verifyCode() {
        guard !verificationCode.isEmpty else {
            alertTitle = "emptyField"
            alertDescription = "checkEmptyField"
            showAlert = true
            return
        }
        
        Task {
            alertTitle = "incorrectCode"
            alertDescription = "verificationCodeTryAgain"
            isLoading = true
            
            (isNavigationActive, showAlert) = await FastVaultService.shared.verifyBackupOTP(
                ecdsaKey: vault.pubKeyECDSA,
                OTPCode: verificationCode
            )
            
            isLoading = false
        }
    }
}

#Preview {
    ServerBackupVerificationView(vault: Vault.example, viewModel: KeygenViewModel())
}
