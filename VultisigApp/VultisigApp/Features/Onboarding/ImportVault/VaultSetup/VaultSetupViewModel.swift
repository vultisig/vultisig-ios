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
    private(set) lazy var form: [FormField] = [
        nameField,
        emailField,
        passwordField,
        passwordConfirmField,
        hintField
    ]

    @Published var emailField = FormField(
        label: "email".localized,
        placeholder: "enterYourEmail".localized,
        validators: [EmailValidator()]
    )

    @Published var nameField = FormField(
        label: "vaultName".localized,
        placeholder: "enterVaultName".localized,
        validators: [VaultNameValidator()]
    )

    @Published var passwordField = FormField(
        label: "password".localized,
        placeholder: "enterPassword".localized,
        validators: [RequiredValidator(errorMessage: "passwordIsRequired".localized)]
    )

    @Published var passwordConfirmField = FormField(
        placeholder: "reEnterPassword".localized,
        validators: []
    )

    @Published var hintField = FormField(
        placeholder: "enterHint".localized
    )

    @Published var referralField = FormField(
        placeholder: "addFriendsReferral".localized
    )

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    var task: Task<Void, Error>?

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

        passwordConfirmField.validators = [
            ClosureValidator(action: { [weak self] value in
                guard let self else { return }
                if !self.isPasswordConfirmValid(value: value) {
                    throw HelperError.runtimeError("passwordMismatch".localized)
                }
            })
        ]

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
