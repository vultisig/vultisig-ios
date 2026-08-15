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
    /// Wires `validForm` to the form's two sources of change: what the user
    /// typed, and which validators are installed to judge it.
    ///
    /// The second source is the one that is easy to miss. Validators routinely
    /// arrive after the value they constrain — an available LP balance, a
    /// stakeable ceiling, a pool's minimum — and no keystroke follows them. A
    /// pipeline driven by `$value` alone would leave `validForm` answering for
    /// the validators the form had *before*, which is exactly the answer the
    /// `transactionBuilder` guards read.
    ///
    /// The value branch hops through the run loop because `@Published` publishes
    /// from `willSet`: validating inline would judge the outgoing value. Validator
    /// changes publish from `didSet` and are already current, so they take effect
    /// synchronously — a form is never briefly valid under rules it no longer has.
    func setupForm() {
        formCancellable?.cancel()
        formCancellable = Publishers.MergeMany(
            form.map { field in
                field.$value
                    .removeDuplicates()
                    .map { _ in () }
                    .receive(on: RunLoop.main)
                    .merge(with: field.validatorsPublisher)
                    .map { _ in field }
                    .eraseToAnyPublisher()
            }
        )
        .sink(weak: self) { form, field in
            // Only the field that changed updates its own visible error, so an
            // error another part of the screen assigned (a whitelist answer, a
            // node with nothing bonded) is not wiped by typing elsewhere.
            try? field.validateErrors()
            form.revalidate()
        }

        // Validators are often installed *before* the pipeline is wired — the
        // Kamino forms build theirs from an awaited vault probe and only then
        // call this. The subject cannot replay those, and the value branch does
        // not report until the run loop turns, so establish the invariant now.
        revalidate()
    }

    /// The Continue-tap path: reveals every field's error, including on fields
    /// the user never touched, and republishes `validForm`.
    ///
    /// Returns the recomputed validity so a submit gate can ask and reveal in
    /// one step. A gate that only wants the answer, without lighting up fields
    /// the user has not reached yet, should call `revalidate()` instead —
    /// refusing without saying why is how a Continue button becomes silently
    /// dead.
    @discardableResult
    func validateErrors() -> Bool {
        form.forEach { field in
            try? field.validateErrors(showing: true)
        }

        return revalidate()
    }

    /// Recomputes `validForm` from the validators installed on every field
    /// *right now*, leaving the fields' visible error state alone.
    ///
    /// This is the single place `validForm` is assigned, so the flag can never
    /// describe a validator set the form has moved past.
    @discardableResult
    func revalidate() -> Bool {
        let isValid = form.allSatisfy { field in
            do {
                try field.validate()
                return true
            } catch {
                return false
            }
        }

        validForm = isValid
        return isValid
    }
}
