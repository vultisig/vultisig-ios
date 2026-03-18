//
//  FastVaultPasswordViewModel.swift
//  VultisigApp
//

import Foundation
import Combine

final class FastVaultPasswordViewModel: ObservableObject, Form {
    @Published var validForm: Bool = false
    let isExistingVault: Bool

    @Published var emailField: FormField
    @Published var passwordField: FormField
    @Published var passwordConfirmField: FormField

    @Published var isLoading: Bool = false
    @Published var isWrongPassword: Bool = false

    private(set) lazy var form: [FormField] = {
        isExistingVault
            ? [emailField, passwordField]
            : [emailField, passwordField, passwordConfirmField]
    }()

    var formCancellable: AnyCancellable?

    private let fastVaultService: FastVaultService = .shared

    init(isExistingVault: Bool) {
        self.isExistingVault = isExistingVault

        self.emailField = FormField(
            placeholder: "enterYourEmail".localized,
            validators: [EmailValidator()]
        )

        self.passwordField = FormField(
            placeholder: "enterPassword".localized,
            validators: [RequiredValidator(errorMessage: "passwordIsRequired".localized)]
        )

        self.passwordConfirmField = FormField(
            placeholder: "verifyPassword".localized,
            validators: [RequiredValidator(errorMessage: "passwordIsRequired".localized)]
        )

        if !isExistingVault {
            passwordConfirmField.validators.append(ClosureValidator(action: { [weak self] value in
                guard let self else { return }
                if self.passwordField.value.isEmpty || value != self.passwordField.value {
                    throw HelperError.runtimeError("passwordMismatch".localized)
                }
            }))
        }
    }

    var fastSignConfig: FastSignConfig {
        FastSignConfig(
            email: emailField.value,
            password: passwordField.value,
            hint: nil,
            isExist: isExistingVault
        )
    }

    func onLoad() {
        setupForm()
    }

    @MainActor func checkPassword(pubKeyECDSA: String) async -> Bool {
        isWrongPassword = false
        isLoading = true
        defer { isLoading = false }

        let isValid = await fastVaultService.get(
            pubKeyECDSA: pubKeyECDSA,
            password: passwordField.value
        )

        guard isValid else {
            isWrongPassword = true
            passwordField.value = ""
            return false
        }

        return true
    }
}
