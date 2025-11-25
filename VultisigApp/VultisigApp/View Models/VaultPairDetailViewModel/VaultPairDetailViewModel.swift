//
//  VaultPairDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import SwiftUI

@MainActor
class VaultPairDetailViewModel: ObservableObject {
    @Published var renderedImage: Image? = nil

    func generateName(vault: Vault) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/ ")
        let cleanVaultName = vault.name.components(separatedBy: invalidCharacters).joined(separator: "-")
        let timestamp = Date().timeIntervalSince1970
        return "VultisigVault-\(cleanVaultName)-\(Int(timestamp)).png"
    }
}
