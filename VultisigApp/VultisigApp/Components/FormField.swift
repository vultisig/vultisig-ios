//
//  FormField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Combine
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

            // Keep rawValue in sync if formatter is present
            rawValue = formatter?.unformat(value) ?? value
        }
    }
    @Published public var rawValue: String

    public var formatter: FormFieldFormatter?

    /// The rules this field is currently judged by. Replacing or appending to
    /// them announces itself through ``validatorsPublisher``, because most of
    /// these arrive late — a balance, a bonded amount, a pool's minimum — long
    /// after the user typed the value they now have to judge.
    public var validators: [FormFieldValidator] {
        didSet { validatorsSubject.send(()) }
    }

    /// Fires once the field's validator set has changed.
    ///
    /// Deliberately not `@Published`: `@Published` publishes from `willSet`, so
    /// a subscriber reading `validators` back would still see the outgoing set
    /// and validate against the rules that were just replaced. This fires from
    /// `didSet`, so the set a subscriber reads is the set it was told about.
    public var validatorsPublisher: AnyPublisher<Void, Never> {
        validatorsSubject.eraseToAnyPublisher()
    }

    private let validatorsSubject = PassthroughSubject<Void, Never>()

    public init(
        initialValue: String = "",
        label: String? = nil,
        placeholder: String? = nil,
        disabled: Bool = false,
        validators: [FormFieldValidator] = [],
        formatter: FormFieldFormatter? = nil
    ) {
        self.label = label
        self.formatter = formatter
        self.placeholder = placeholder
        self.disabled = disabled
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

    public func validateErrors(showing: Bool = false) throws {
        let showError = touched || value.isNotEmpty

        do {
            try validate()
            self.error = nil
            self.valid = true
        } catch {
            self.error = (showError || showing) ? error.localizedDescription : nil
            self.valid = false
            throw error
        }
    }

    public func validate() throws {
        for validator in validators {
            try validator.validate(value: rawValue)
        }
    }
}
