//
//  DateExtension.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 19.11.2024.
//

import Foundation

extension Date: RawRepresentable {

    public var rawValue: String {
        self.timeIntervalSinceReferenceDate.description
    }

    public init?(rawValue: String) {
        self = Date(timeIntervalSinceReferenceDate: Double(rawValue) ?? 0.0)
    }
}
