//
//  VaultDetailQRCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct VaultDetailQRCode: View {
    let vault: Vault
    
    var body: some View {
        VStack(spacing: 10) {
            qrCodeContent
            name
            ECDSAKey
            EdDSAKey
        }
        .padding(22)
        .frame(width: 320, height: 460)
        .background(LinearGradient.primaryGradientLinear)
        .cornerRadius(25)
    }
    
    var qrCodeContent: some View {
        ZStack {
            qrCode
            logo
        }
    }
    
    var qrCode: some View {
        getQRCode(vault: vault)
            .resizable()
            .frame(width: 180, height: 180)
            .scaledToFit()
            .padding(3)
            .cornerRadius(10)
            .foregroundColor(.neutral100)
    }
    
    var logo: some View {
        Image("VultisigLogoTemplate")
            .resizable()
            .frame(width: 32, height: 32)
            .foregroundColor(.logoBlue)
            .padding(8)
            .background(Color.neutral0)
            .cornerRadius(10)
    }
    
    var name: some View {
        Text(vault.name)
            .font(.body20MenloBold)
            .foregroundColor(.neutral0)
            .padding(.top, 20)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    var ECDSAKey: some View {
        VStack {
            Text(NSLocalizedString("ECDSAKey", comment: ""))
                .font(.body14MontserratSemiBold)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
            
            Text(vault.pubKeyECDSA)
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
    }
    
    var EdDSAKey: some View {
        VStack {
            Text(NSLocalizedString("EdDSAKey", comment: ""))
                .font(.body14MontserratSemiBold)
                .foregroundColor(.neutral0)
                .lineLimit(3)
                .multilineTextAlignment(.center)
            
            Text(vault.pubKeyEdDSA)
                .font(.body12MontserratSemiBold)
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
        let id = "sha256(\(name) - \(ecdsaKey) - \(eddsaKey) - \(hexCode))"
        
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
    VaultDetailQRCode(vault: Vault.example)
}
