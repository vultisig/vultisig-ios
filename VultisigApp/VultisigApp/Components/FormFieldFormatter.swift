//
//  FormFieldFormatter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

public protocol FormFieldFormatter {
    func format(_ string: String) -> String
    func unformat(_ string: String) -> String
}
