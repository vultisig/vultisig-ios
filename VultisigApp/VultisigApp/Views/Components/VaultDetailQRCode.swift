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
        .frame(width: 300, height: 400)
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
        Rectangle()
            .frame(width: 180, height: 180)
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
    }
    
    var ECDSAKey: some View {
        Text(vault.pubKeyECDSA)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var EdDSAKey: some View {
        Text(vault.pubKeyEdDSA)
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
            .offset(y: -8)
    }
}

#Preview {
    VaultDetailQRCode(vault: Vault.example)
}
