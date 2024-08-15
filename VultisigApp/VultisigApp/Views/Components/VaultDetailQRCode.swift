//
//  VaultDetailQRCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct VaultDetailQRCode: View {
    let vault: Vault
    
    @StateObject var viewModel = VaultDetailQRCodeViewModel()
    
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
            .frame(width: 240, height: 240)
            .scaledToFit()
            .padding(3)
            .cornerRadius(10)
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
            .padding(.top, 10)
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
        let vaultPublicKeyExport = viewModel.getVaultPublicKeyExport(vault: vault)
        
        do{
            let data = try JSONEncoder().encode(vaultPublicKeyExport)
            return Utils.generateQRCodeImage(
                from: String(data: data, encoding: .utf8) ?? "",
                tint: .white,
                background: .clear
            )
        } catch {
            print("failed to create vault public key export: \(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }
}

#Preview {
    VaultDetailQRCode(vault: Vault.example)
}
