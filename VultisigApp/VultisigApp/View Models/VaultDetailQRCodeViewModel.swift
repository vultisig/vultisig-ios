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
    
    func render(vault: Vault, displayScale: CGFloat) {
#if os(iOS)
        let renderer = ImageRenderer(content: VaultDetailQRCode(vault: vault))
#elseif os(macOS)
        let renderer = ImageRenderer(content: VaultDetailMacQRCode(vault: vault))
#endif

        renderer.scale = displayScale

#if os(iOS)
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
#elseif os(macOS)
        if let nsImage = renderer.nsImage {
            renderedImage = Image(nsImage: nsImage)
        }
#endif
    }
    
    func generateName(vault: Vault) -> String {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        return "Vultisig-\(vault.name)-\(id.suffix(3)).png"
    }
    
    func getVaultPublicKeyExport(vault: Vault) -> VaultPublicKeyExport {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        return VaultPublicKeyExport(uid: id, name: name, public_key_ecdsa: ecdsaKey, public_key_eddsa: eddsaKey, hex_chain_code: hexCode)
    }
}
