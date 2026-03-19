//
//  ClosureValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/11/2025.
//

struct ClosureValidator: FormFieldValidator {
    let action: (String) throws -> Void

    func validate(value: String) throws {
        try action(value)
    }
}
