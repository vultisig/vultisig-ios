//
//  FormFieldValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

public protocol FormFieldValidator {
    func validate(value: String) throws
}

public extension FormFieldValidator {
    func validateNonThrowable(value: String) -> Bool {
        do {
            try validate(value: value)
            return true
        } catch {
            return false
        }
    }
}
