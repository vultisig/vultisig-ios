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
        // For secure setup, only name is required
        // For fast setup, all fields are required
        if setupType.requiresFastSign {
            return [
                nameField,
                emailField,
                passwordField,
                passwordConfirmField,
                hintField
            ]
        } else {
            return [nameField]
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

    /// Whether to show FastSign fields (email and password)
    var showFastSignFields: Bool {
        setupType.requiresFastSign
    }

    init(setupType: KeyImportSetupType) {
        self.setupType = setupType

        // Always require name field
        self.nameField = FormField(
            label: "vaultName".localized,
            placeholder: "enterVaultName".localized,
            validators: [VaultNameValidator()]
        )

        // For fast setup with FastSign, email and password validators are required
        // For non-FastSign setup, fields are not visible so no validators needed
        if setupType.requiresFastSign {
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
    }

    func setReferralError(_ error: String?) {
        referralField.error = error
        referralField.valid = error == nil
    }

    func clearReferral() {
        referralField.value = ""
        referralField.valid = false
        referralField.error = nil
        referralField.touched = false
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
