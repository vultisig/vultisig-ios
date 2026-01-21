//
//  VaultNameValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/12/2025.
//

import Foundation
import SwiftData

struct VaultNameValidator: FormFieldValidator {
    let vaults: [Vault]

    init() {
        let fetchVaultDescriptor = FetchDescriptor<Vault>()
        vaults = (try? Storage.shared.modelContext.fetch(fetchVaultDescriptor)) ?? []
    }

    func validate(value: String) throws {
        if value.isEmpty {
            throw HelperError.runtimeError("enterVaultName".localized)
        }

        for vault in vaults {
            if vault.name.caseInsensitiveCompare(value) == .orderedSame {
                throw HelperError.runtimeError("vaultNameExists".localized.replacingOccurrences(of: "%s", with: value))
            }
        }
    }
}
