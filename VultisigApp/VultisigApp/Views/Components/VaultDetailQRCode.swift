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
        VStack(spacing: 12) {
            name
            uid
            qrCodeContent
            webLink
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.colors.bgSurface1.opacity(0.6))
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
    }
    
    var logo: some View {
        Image("VultisigLogoTemplate")
            .resizable()
            .frame(width: 32, height: 32)
            .foregroundColor(Theme.colors.bgPrimary)
            .padding(8)
            .background(Theme.colors.textPrimary)
            .cornerRadius(10)
    }
    
    var name: some View {
        Text(vault.name)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    var uid: some View {
        Text("UID: \(viewModel.getId(for: vault))")
            .font(Theme.fonts.footnote)
            .foregroundColor(Theme.colors.textSecondary)
            .multilineTextAlignment(.center)
    }
    
    var webLink: some View {
        Text("vultisig.com")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
    }
    
    func getQRCode(vault: Vault) -> Image {
        let vaultPublicKeyExport = viewModel.getVaultPublicKeyExport(vault: vault)
        do {
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
