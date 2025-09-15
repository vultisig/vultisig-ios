//
//  VaultServerBackupViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/09/2025.
//

import Combine
import SwiftUI

final class VaultServerBackupViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var emailError: String?
    @Published var passwordError: String?
    @Published var requestError: String?
    @Published var isLoading = false
    
    
    @Published var showSuccess = false
    @Published var showAlert: Bool = false
    @Published var alertError: ResendVaultShareError?
    
    var cancellables = Set<AnyCancellable>()
    
    var validForm: Bool {
        email.isNotEmpty && password.isNotEmpty && emailError == nil && passwordError == nil && !isLoading
    }
    
    var validEmail: Bool {
        emailError == nil && email.isNotEmpty
    }
    
    var validPassword: Bool {
        passwordError == nil && password.isNotEmpty
    }
    
    let service = VultiServerService()
    
    func onLoad() {
        $email
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] email in
                guard let self else { return }
                self.validate(email: email)
            }
            .store(in: &cancellables)
        
        $password
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] password in
                guard let self else { return }
                self.validate(password: password)
            }
            .store(in: &cancellables)
    }
    
    func validate(email: String) {
        if email.isEmpty || email.trimmingCharacters(in: .whitespaces).isEmpty {
            emailError = "emailIsRequired".localized
        } else if !email.isValidEmail {
            emailError = "invalidEmailPleaseCheck".localized
        } else {
            emailError = nil
        }
    }
    
    func validate(password: String) {
        if password.isEmpty {
            passwordError = "passwordIsRequired".localized
        } else {
            passwordError = nil
        }
    }
    
    func requestServerVaultShare(vault: Vault) async {
        await MainActor.run {
            showAlert = false
            isLoading = true
        }
        
        do {
            try await service.resendVaultShare(request: ResendVaultShareRequest(pubKeyECDSA: vault.pubKeyECDSA, email: email, password: password))
            
            await MainActor.run {
                isLoading = false
                alertError = nil
                showSuccess = true
            }
        } catch {
            await MainActor.run {
                isLoading = false
                alertError = error as? ResendVaultShareError
                showAlert = true
            }
        }
    }
}
