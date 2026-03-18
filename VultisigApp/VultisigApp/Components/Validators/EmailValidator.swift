//
//  EmailValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

struct EmailValidator: FormFieldValidator {
    func validate(value: String) throws {
        if value.isEmpty || value.trimmingCharacters(in: .whitespaces).isEmpty {
            throw HelperError.runtimeError("emailIsRequired".localized)
        } else if !value.isValidEmail {
            throw HelperError.runtimeError("invalidEmailPleaseCheck".localized)
        }
    }
}
