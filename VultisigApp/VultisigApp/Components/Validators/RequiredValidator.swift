//
//  RequiredValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/11/2025.
//

struct RequiredValidator: FormFieldValidator {
    let errorMessage: String

    func validate(value: String) throws {
        guard value.isNotEmpty else {
            throw HelperError.runtimeError(errorMessage)
        }
    }
}
