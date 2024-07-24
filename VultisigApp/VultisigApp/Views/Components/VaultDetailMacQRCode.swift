//
//  VaultDetailMacQRCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct VaultDetailMacQRCode: View {
    let vault: Vault
    
    var body: some View {
        VStack(spacing: 32) {
            qrCodeContent
            name
            ECDSAKey
            EdDSAKey
        }
        .padding(22)
        .frame(width: 960, height: 1380)
        .background(LinearGradient.primaryGradientLinear)
    }
    
    var qrCodeContent: some View {
        ZStack {
            qrCode
            logo
        }
    }
    
    var qrCode: some View {
        getQRCode(vault: vault)
            .interpolation(.none)
            .resizable()
            .frame(width: 700, height: 700)
            .scaledToFit()
            .padding(3)
            .cornerRadius(10)
            .foregroundColor(.neutral100)
    }
    
    var logo: some View {
        Image("VultisigLogoTemplate")
            .resizable()
            .frame(width: 64, height: 64)
            .foregroundColor(.logoBlue)
            .padding(8)
            .background(Color.neutral0)
            .cornerRadius(10)
    }
    
    var name: some View {
        Text(vault.name)
            .font(.title40MenloBold)
            .foregroundColor(.neutral0)
            .padding(.top, 20)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    var ECDSAKey: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("ECDSAKey", comment: ""))
                .font(.body24MontserratMedium)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
            
            Text(vault.pubKeyECDSA)
                .font(.body20MontserratMedium)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
    }
    
    var EdDSAKey: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("EdDSAKey", comment: ""))
                .font(.body24MontserratMedium)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
            
            Text(vault.pubKeyEdDSA)
                .font(.body20MontserratMedium)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
    }
    
    func getQRCode(vault: Vault) -> Image {
        let name = vault.name
        let ecdsaKey = vault.pubKeyECDSA
        let eddsaKey = vault.pubKeyEdDSA
        let hexCode = vault.hexChainCode
        let id = "\(name)-\(ecdsaKey)-\(eddsaKey)-\(hexCode)".sha256()
        
        let data = """
        {
            "uid": \(id),
            "name" : \(name),
            "public_key_ecdsa": \(ecdsaKey),
            "public_key_eddsa": \(eddsaKey),
            "hex_chain_code": \(hexCode)
        }
        """
        
        return Utils.generateQRCodeImage(from: data)
    }

}

#Preview {
    VaultDetailMacQRCode(vault: Vault.example)
}
