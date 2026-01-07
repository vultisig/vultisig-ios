//
//  ScannerResultManager.swift
//  VultisigApp
//
//  Created by Assistant on 2025-12-17.
//

import Foundation
import SwiftUI

class ScannerResultManager: ObservableObject {
    static let shared = ScannerResultManager()

    @Published private var results: [UUID: AddressResult?] = [:]

    private init() {}

    func getBinding(for id: UUID) -> Binding<AddressResult?> {
        Binding(
            get: { self.results[id] ?? nil },
            set: { self.results[id] = $0 }
        )
    }

    func setResult(_ result: AddressResult?, for id: UUID) {
        results[id] = result
    }

    func getResult(for id: UUID) -> AddressResult? {
        results[id] ?? nil
    }

    func clearResult(for id: UUID) {
        results.removeValue(forKey: id)
    }
}
