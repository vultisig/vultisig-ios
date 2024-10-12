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
        VStack(spacing: 0) {
            name
            uid
            Spacer()
            qrCodeContent
            Spacer()
            webLink
        }
        .padding(16)
        .frame(width: 310, height: 400)
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
            .frame(width: 230, height: 230)
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
    
    var uid: some View {
        Group {
            Text("UID\n")
                .font(.body16MontserratSemiBold) +
            Text(viewModel.getId(for: vault))
                .font(.body12Montserrat)
        }
        .multilineTextAlignment(.center)
        .foregroundColor(.neutral0)
        .padding(.top, 10)
        .padding(.horizontal, 14)
    }
    
    var webLink: some View {
        Text("vultisig.com")
            .font(.body18MontserratMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
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
