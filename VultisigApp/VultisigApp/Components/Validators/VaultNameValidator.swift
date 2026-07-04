//
//  VaultNameValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation
import SwiftData

struct VaultNameValidator: FormFieldValidator {
    private let vaultNames: Set<String>

    init() {
        let descriptor = FetchDescriptor<Vault>()
        let vaults = (try? Storage.shared.modelContext.fetch(descriptor)) ?? []
        self.init(existingNames: vaults.map(\.name))
    }

    init(existingNames: [String]) {
        vaultNames = Set(existingNames.map { Self.normalize($0) })
    }

    func validate(value: String) throws {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw HelperError.runtimeError("enterVaultName".localized)
        }
        guard !vaultNames.contains(Self.normalize(name)) else {
            throw HelperError.runtimeError("vaultNameExists".localized.replacingOccurrences(of: "%s", with: name))
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
