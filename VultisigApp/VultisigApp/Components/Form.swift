//
//  Form.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

@MainActor
protocol Form: AnyObject {
    var validForm: Bool { get set }
    var form: [FormField] { get }
    var formCancellable: AnyCancellable? { get set }
}

extension Form {
    func setupForm() {
        formCancellable?.cancel()
        formCancellable = form
            .map { field in
                field.$value
                    .removeDuplicates()
                    .receive(on: RunLoop.main)
                    .map { _ in
                        do {
                            try field.validateErrors()
                            return true
                        } catch {
                            return false
                        }
                    }
            }
            .combineLatest()
            .sink(weak: self) { form, validations in
                form.validForm = validations.allSatisfy { $0 }
            }
    }

    func validateErrors() {
        form.forEach {  field in
            try? field.validateErrors(showing: true)
        }
    }

    /// Re-runs every validator now, refreshes `validForm` from the result, and
    /// reports it — surfacing field errors exactly as `validateErrors()` does.
    ///
    /// `setupForm()` only recomputes `validForm` when a field's *value*
    /// publishes. A form that installs a validator **later**, once a balance or
    /// a limit arrives from the network, therefore keeps whatever `validForm`
    /// was decided before that validator existed: type the amount first, let
    /// the limit land second, and `validForm` is still the stale `true`.
    /// Submit paths gated on an asynchronously-installed validator must ask
    /// this rather than read the cached value.
    @discardableResult
    func revalidate() -> Bool {
        var isValid = true
        for field in form {
            do {
                try field.validateErrors(showing: true)
            } catch {
                isValid = false
            }
        }
        validForm = isValid
        return isValid
    }
}
