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
        vaultNames = Set(vaults.map { $0.name.lowercased() })
    }

    func validate(value: String) throws {
        guard !value.isEmpty else {
            throw HelperError.runtimeError("enterVaultName".localized)
        }
        guard !vaultNames.contains(value.lowercased()) else {
            throw HelperError.runtimeError("vaultNameExists".localized.replacingOccurrences(of: "%s", with: value))
        }
    }
}
