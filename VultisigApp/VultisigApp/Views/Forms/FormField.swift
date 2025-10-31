//
//  FormField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

public class FormField: ObservableObject {
    @Published public var label: String?
    @Published public var valid = false
    @Published public var error: String? = nil
    @Published public var disabled: Bool
    @Published public var touched: Bool
    @Published public var firstResponder: Bool = false
    @Published public var placeholder: String?
    @Published public var footer: String?
    @Published public var value: String {
        didSet {
            if value.isNotEmpty {
                touched = true
            }
            if !validatesOnBlur {
                validateErrors()
            } else {
                error = nil
            }
            // Keep rawValue in sync if formatter is present
            rawValue = formatter?.unformat(value) ?? value
        }
    }
    @Published public var rawValue: String

    public var formatter: FormFieldFormatter?
    public var validatesOnBlur: Bool
    public var validators: [FormFieldValidator]

    public init(
        initialValue: String = "",
        label: String? = nil,
        placeholder: String? = nil,
        disabled: Bool = false,
        validatesOnBlur: Bool = false,
        validators: [FormFieldValidator] = [],
        formatter: FormFieldFormatter? = nil
    ) {
        self.label = label
        self.formatter = formatter
        self.placeholder = placeholder
        self.disabled = disabled
        self.validatesOnBlur = validatesOnBlur
        self.validators = validators
        self.touched = false
        self.rawValue = initialValue
        if let formatter = formatter {
            self.value = formatter.format(initialValue)
        } else {
            self.value = initialValue
        }
    }

    public func formatIfNeeded() {
        if let formatter {
            value = formatter.format(value)
        }
    }

    public func validateErrors() {
        guard touched || value.isNotEmpty else { return }

        do {
            try validate()
            self.error = nil
            self.valid = true
        } catch {
            self.error = error.localizedDescription
            self.valid = false
        }
    }

    public func validate() throws {
        for validator in validators {
            try validator.validate(value: rawValue)
        }
    }

    public func onBlur() {
        guard validatesOnBlur else { return }
        validateErrors()
    }
}
