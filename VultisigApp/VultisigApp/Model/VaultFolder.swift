//
//  VaultFolder.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import Foundation

class VaultFolder {
    let folderName: String
    let containedVaults: [Vault]
    
    init(folderName: String, containedVaults: [Vault]) {
        self.folderName = folderName
        self.containedVaults = containedVaults
    }
}
