//
//  VaultDetailQRCodeViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import Foundation
import SwiftUI

@MainActor
class VaultDetailQRCodeViewModel: ObservableObject {
    @Published var renderedImage: Image? = nil
    
    func generateName(vault: Vault) -> String {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        return "VultisigQR-\(vault.name)-\(id.suffix(3)).png"
    }
    
    func getVaultPublicKeyExport(vault: Vault) -> VaultPublicKeyExport {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        return VaultPublicKeyExport(uid: id, name: name, public_key_ecdsa: ecdsaKey, public_key_eddsa: eddsaKey, hex_chain_code: hexCode)
    }
    
    func getId(vault: Vault) -> String {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        return "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
    }
}
