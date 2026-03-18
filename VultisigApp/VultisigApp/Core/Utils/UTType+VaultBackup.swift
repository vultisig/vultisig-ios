//
//  UTType+VaultBackup.swift
//  VultisigApp
//

import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for .bak vault backup files
    static var vaultBackup: UTType {
        UTType(exportedAs: "com.vultisig.backup")
    }

    /// Custom UTType for .vult vault files
    static var vaultFile: UTType {
        UTType(exportedAs: "com.vultisig.vault")
    }
}
