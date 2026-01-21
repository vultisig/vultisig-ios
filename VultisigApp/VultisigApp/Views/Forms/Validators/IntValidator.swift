//
//  IntValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation

struct IntValidator: FormFieldValidator {
    let errorMessage: String

    init(errorMessage: String = "invalidIntegerError".localized) {
        self.errorMessage = errorMessage
    }

    func validate(value: String) throws {
        guard !value.isEmpty else {
            // Allow empty values - use RequiredValidator if needed
            return
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespaces)

        guard Int(trimmedValue) != nil else {
            throw HelperError.runtimeError(errorMessage)
        }
    }
}
