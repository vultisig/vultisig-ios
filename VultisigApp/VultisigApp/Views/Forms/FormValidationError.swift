//
//  FormValidationError.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

public struct FormValidationError: Error, CustomStringConvertible, LocalizedError {
    /// Human readable description
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public var errorDescription: String? {
        description
    }
}
