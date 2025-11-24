//
//  IntValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation

struct IntValidator: FormFieldValidator {
    let errorMessage: String
    
    init(errorMessage: String = "mustBeInteger".localized) {
        self.errorMessage = errorMessage
    }
    
    func validate(value: String) throws {
        guard !value.isEmpty else {
            // Allow empty values - use RequiredValidator if needed
            return
        }
        
        // Check if the value contains only digits (and optionally whitespace)
        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        
        guard Int(trimmedValue) != nil else {
            throw HelperError.runtimeError(errorMessage)
        }
        
        // Also ensure there are no decimal points or other non-integer characters
        guard !trimmedValue.contains(".") && !trimmedValue.contains(",") else {
            throw HelperError.runtimeError(errorMessage)
        }
    }
}
