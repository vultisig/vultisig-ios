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
            .font(.title60MenloBold)
            .foregroundColor(.neutral0)
            .padding(.top, 60)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    var uid: some View {
        Text("UID: \(vault.localPartyID)")
            .font(.title36MontserratSemiBold)
            .foregroundColor(.neutral0)
            .padding(.top, 10)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
    
    var webLink: some View {
        Text("vultisig.com")
            .font(.title36MontserratSemiBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.bottom, 32)
    }
    
    func getQRCode(vault: Vault) -> Image {
        let vaultPublicKeyExport = viewModel.getVaultPublicKeyExport(vault: vault)
        
        do{
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
