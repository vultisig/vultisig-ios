//
//  ServerBackupVerificationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

import SwiftUI
import SwiftData

struct ServerBackupVerificationView: View {
    let vault: Vault
    let selectedTab: SetupVaultState?
    @ObservedObject var viewModel: KeygenViewModel
    
    @State var verificationCode = ""
    
    @State var isLoading: Bool = false
    @State var isNavigationActive: Bool = false
    
    @State var alertTitle = "incorrectCode"
    @State var alertDescription = "verificationCodeTryAgain"
    @State var showAlert: Bool = false
    @State var showHomeView: Bool = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            Background()
            container
            
            if isLoading {
                loader
            }
        }
        .navigationDestination(isPresented: $isNavigationActive) {
            if showHomeView {
                HomeView()
            } else {
                BackupVaultNowView(vault: vault, selectedTab: selectedTab)
            }
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
            FilledButton(title: "continue")
        }
        .grayscale(verificationCode.isEmpty ? 1 : 0)
        .disabled(verificationCode.isEmpty)
    }
    
    var cancelButton: some View {
        Button {
            deleteVault()
        } label: {
            OutlineButton(title: "cancel", gradient: LinearGradient.cancelRed)
        }
        .padding(.bottom, 30)
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
}

#Preview {
    ServerBackupVerificationView(vault: Vault.example, selectedTab: .secure, viewModel: KeygenViewModel())
}
