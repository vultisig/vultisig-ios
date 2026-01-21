//
//  VaultDetailMacQRCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct VaultDetailMacQRCode: View {
    let vault: Vault

    @StateObject var viewModel = VaultDetailQRCodeViewModel()

    var body: some View {
        VStack(spacing: 32) {
            name
            uid
            Spacer()
            qrCodeContent
            Spacer()
            webLink
        }
        .padding(22)
        .frame(width: 960, height: 1400)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.colors.bgSurface1.opacity(0.6))
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
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
            .foregroundColor(Theme.colors.textPrimary)
            .padding(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
    }

    var logo: some View {
        Image("VultisigLogoTemplate")
            .resizable()
            .frame(width: 64, height: 64)
            .foregroundColor(Theme.colors.bgPrimary)
            .padding(8)
            .background(Theme.colors.textPrimary)
            .cornerRadius(10)
    }

    var name: some View {
        Text(vault.name)
            .font(Theme.fonts.display)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(.top, 60)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    var uid: some View {
        Group {
            Text("UID\n")
                .font(Theme.fonts.largeTitle) +
            Text(viewModel.getId(for: vault))
                .font(Theme.fonts.largeTitle)
        }
        .multilineTextAlignment(.center)
        .foregroundColor(Theme.colors.textPrimary)
        .padding(.top, 10)
        .padding(.horizontal, 14)
    }

    var webLink: some View {
        Text("vultisig.com")
            .font(Theme.fonts.largeTitle)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 32)
    }

    func getQRCode(vault: Vault) -> Image {
        let vaultPublicKeyExport = viewModel.getVaultPublicKeyExport(vault: vault)
        do {
            let data = try JSONEncoder().encode(vaultPublicKeyExport)
            return Utils.generateQRCodeImage(from: String(data: data, encoding: .utf8) ?? "")
        } catch {
            print("failed to create vault public key export: \(error.localizedDescription)")
            return Image(systemName: "xmark")
        }
    }

}

#Preview {
    VaultDetailMacQRCode(vault: Vault.example)
}
