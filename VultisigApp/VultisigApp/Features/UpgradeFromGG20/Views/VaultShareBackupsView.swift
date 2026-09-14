//
//  VaultShareBackupsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

struct VaultShareBackupsView: View {
    let vault: Vault
    var useServer = false
    @State private var resolvePresence = false

    @Environment(\.router) var router

    var body: some View {
        ZStack {
            Background()
            content
        }
        .crossPlatformSheet(isPresented: $resolvePresence) {
            FastVaultPresenceGate(vault: vault) { hosted in
                resolvePresence = false
                if hosted { navigateHosted() } else { navigatePaired() }
            }
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
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .font(Theme.fonts.title1)
    }

    var button: some View {
        ZStack {
            if useServer {
                migrateFastVault
            } else {
                migrateSecureVault
            }
        }
        .padding(.vertical, 36)
    }

    var migrateSecureVault: some View {
        PrimaryButton(title: "next") {
            navigatePaired()
        }
        .frame(width: 120)
    }

    var migrateFastVault: some View {
        PrimaryButton(title: "next") {
            resolvePresence = true
        }
    }

    private func navigatePaired() {
        router.navigate(to: KeygenRoute.peerDiscovery(
            tssType: .Migrate,
            vault: vault,
            selectedTab: .secure,
            fastSignConfig: nil,
            keyImportInput: nil,
            setupType: nil,
            singleKeygenType: nil
        ))
    }

    private func navigateHosted() {
        router.navigate(to: KeygenRoute.fastVaultPassword(
            tssType: .Migrate,
            vault: vault,
            selectedTab: vault.signers.count == 2 ? .fast : .active,
            isExistingVault: true,
            singleKeygenType: nil
        ))
    }

}

#Preview {
    VaultShareBackupsView(vault: Vault.example)
}

#if os(iOS)
extension VaultShareBackupsView {
    var content: some View {
        ZStack {
            VStack {
                image
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                description
                button
            }
        }
        .padding(36)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
}
#endif

#if os(macOS)
extension VaultShareBackupsView {
    var content: some View {
        VStack(spacing: 0) {
            Spacer()
            image
            Spacer()
            description
            button
        }
        .padding(.bottom, 36)
        .crossPlatformToolbar()
    }
}
#endif
