//
//  VaultSetupViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation
import Combine

final class VaultSetupViewModel: ObservableObject, Form {
    @Published var validForm: Bool = false
    private let setupType: KeyImportSetupType

    private(set) lazy var form: [FormField] = {
        // For fast setup, only name is required
        // For secure setup, all fields are required
        if setupType.requiresFastSign {
            return [
                nameField,
                referralField,
                emailField,
                passwordField,
                passwordConfirmField,
                hintField
            ]
        } else {
            return [nameField, referralField]
        }
    }()

    @Published var emailField: FormField
    @Published var nameField: FormField
    @Published var passwordField: FormField
    @Published var passwordConfirmField: FormField

    @Published var hintField = FormField(
        placeholder: "enterHint".localized
    )

    @Published var referralField = FormField(
        placeholder: "addFriendsReferral".localized
    )

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    var task: Task<Void, Error>?

    /// Whether to show FastSign fields (email and password)
    var showFastSignFields: Bool {
        setupType.requiresFastSign ?? true
    }

    init(setupType: KeyImportSetupType) {
        self.setupType = setupType

        // Always require name field
        self.nameField = FormField(
            label: "vaultName".localized,
            placeholder: "enterVaultName".localized,
            validators: [VaultNameValidator()]
        )

        // For fast setup, email and password have no validators (optional)
        // For secure/default, they are required
        if setupType.requiresFastSign == false {
            self.emailField = FormField(
                label: "email".localized,
                placeholder: "enterYourEmail".localized,
                validators: [EmailValidator()]
            )

            self.passwordField = FormField(
                label: "password".localized,
                placeholder: "enterPassword".localized,
                validators: [RequiredValidator(errorMessage: "passwordIsRequired".localized)]
            )

            self.passwordConfirmField = FormField(
                placeholder: "reEnterPassword".localized,
                validators: [RequiredValidator(errorMessage: "passwordIsRequired".localized)]
            )
            
            passwordConfirmField.validators.append(ClosureValidator(action: { [weak self] value in
                guard let self else { return }
                if !self.isPasswordConfirmValid(value: value) {
                    throw HelperError.runtimeError("passwordMismatch".localized)
                }
            }))
        } else {
            self.emailField = FormField(
                label: "email".localized,
                placeholder: "enterYourEmail".localized,
                validators: []
            )

            self.passwordField = FormField(
                label: "password".localized,
                placeholder: "enterPassword".localized,
                validators: []
            )

            self.passwordConfirmField = FormField(
                placeholder: "reEnterPassword".localized,
                validators: []
            )
        }
    }
    
    var vaultName: String {
        nameField.value
    }
    
    var fastConfig: FastSignConfig {
        FastSignConfig(
            email: emailField.value,
            password: passwordField.value,
            hint: hintField.value.nilIfEmpty,
            isExist: false
        )
    }
    
    func onLoad() {
        setupForm()

        referralField.$value
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .sink(weak: self) { viewModel, value in
                guard !value.isEmpty else {
                    viewModel.referralField.error = nil
                    return
                }

                guard value.count <= 4 else {
                    viewModel.referralField.error = "referralLaunchCodeLengthError".localized
                    return
                }

                viewModel.task?.cancel()
                viewModel.task = Task {
                    do {
                        try await ReferredCodeInteractor().verify(code: value)
                        if Task.isCancelled { return }
                        await MainActor.run { viewModel.referralField.error = nil }
                    } catch {
                        if Task.isCancelled { return }
                        await MainActor.run { viewModel.referralField.error = error.localizedDescription }
                    }
                }
            }
            .store(in: &cancellables)

    }
    
    func isPasswordConfirmValid(value: String) -> Bool {
        passwordField.value.isNotEmpty && value == passwordField.value
    }
    
    func getVault(keyImportInput: KeyImportInput?) -> Vault {
        let vault = Vault(
            name: vaultName,
            libType: keyImportInput != nil ? .KeyImport : nil,
        )
        
        if referralField.value.isNotEmpty, referralField.valid {
            vault.referredCode = ReferredCode(code: referralField.value, vault: vault)
        }
        
        return vault
    }
}
