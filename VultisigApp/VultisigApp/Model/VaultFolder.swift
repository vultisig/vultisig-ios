//
//  VaultFolder.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import Foundation

class VaultFolder: Hashable {
    let id = UUID()
    let folderName: String
    let containedVaults: [Vault]
    
    init(folderName: String, containedVaults: [Vault]) {
        self.folderName = folderName
        self.containedVaults = containedVaults
    }
    
    static func == (lhs: VaultFolder, rhs: VaultFolder) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static let example = VaultFolder(folderName: "Main Folder", containedVaults: [Vault.example])
}
