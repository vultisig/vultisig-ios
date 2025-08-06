//
//  VaultShareBackupsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

struct VaultShareBackupsView: View {
    let vault: Vault
    
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var image: some View {
        Image("VaultShareBackupsImage")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 512, maxHeight: 512)
            .scaleEffect(1.1)
            .padding(-36)
    }
    
    var description: some View {
        Group {
            Text(NSLocalizedString("vaultShareBackupsViewTitle1", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("vaultShareBackupsViewTitle2", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .font(Theme.fonts.title1)
    }
    
    var button: some View {
        ZStack {
            if vault.isFastVault {
                migrateFastVault
            } else {
                migrateSecureVault
            }
        }
        .padding(.vertical, 36)
    }
    
    var migrateSecureVault: some View {
        PrimaryNavigationButton(title: "next") {
            PeerDiscoveryView(
                tssType: .Migrate,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: nil
            )
        }.frame(width: 120)
    }
    
    var migrateFastVault: some View {
        PrimaryNavigationButton(title: "next") {
            FastVaultEmailView(
                tssType: .Migrate,
                vault: vault,
                selectedTab: .fast,
                fastVaultExist: true
            )
        }
    }
}

#Preview {
    VaultShareBackupsView(vault: Vault.example)
}
