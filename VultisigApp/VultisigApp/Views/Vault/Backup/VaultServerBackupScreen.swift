//
//  VaultServerBackupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/09/2025.
//

import SwiftUI

struct VaultServerBackupScreen: View {
    let vault: Vault
    @StateObject var viewModel = VaultServerBackupViewModel()
    @State var secureTextField: Bool = true
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Screen {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        emailTextField
                        passwordTextField
                    }
                }
                
                PrimaryButton(title: "requestServerVaultShare".localized) {
                    Task {
                        await viewModel.requestServerVaultShare(vault: vault)
                    }
                }
                .disabled(!viewModel.validForm)
            }
        }
        .overlay(viewModel.isLoading ? Loader() : nil)
        .onLoad(perform: viewModel.onLoad)
        .alert(isPresented: $viewModel.showAlert) {
            if viewModel.alertError == nil {
                successAlert
            } else {
                errorAlert
            }
        }
    }
    
    var emailTextField: some View {
        CommonTextField(
            text: $viewModel.email,
            label: "email".localized,
            placeholder: "enterYourEmail".localized,
            error: $viewModel.emailError
        )
        #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
        #endif
    }
    
    var passwordTextField: some View {
        SecureTextField(
            value: $viewModel.password,
            label: "password".localized,
            placeholder: "enterYourPassword".localized,
            error: $viewModel.passwordError
        )
    }
    
    var successAlert: Alert {
        Alert(
            title: Text("requestServerVaultShare".localized),
            message: Text("requestServerVaultShareSuccess".localized),
            dismissButton: .default(Text("ok".localized)) {
                dismiss()
            }
        )
    }
    
    var errorAlert: Alert {
        Alert(
            title: Text("requestServerVaultShare".localized),
            message: Text((viewModel.alertError ?? ResendVaultShareError.unknown).localizedDescription),
            dismissButton: .default(Text("ok".localized))
        )
    }
}

