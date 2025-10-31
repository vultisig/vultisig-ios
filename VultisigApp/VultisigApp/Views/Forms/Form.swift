//
//  Form.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

public protocol Form: AnyObject {
    var validForm: Bool { get set }
    var form: [FormField] { get }
    var formCancellable: AnyCancellable? { get set }
}

public extension Form {
    func setupForm() {
        formCancellable?.cancel()
        formCancellable = form
            .map { field in
                field.$value
                    .receive(on: DispatchQueue.main)
                    .map { _ in
                        do {
                            try field.validate()
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

    func clearForm() {
        form.forEach {
            $0.touched = false
            $0.value = ""
            $0.error = nil
        }
    }
}
