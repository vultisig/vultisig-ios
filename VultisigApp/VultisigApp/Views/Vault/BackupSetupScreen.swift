//
//  BackupPasswordSetupView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-13.
//

import SwiftUI
import RiveRuntime

struct VaultBackupNowScreen: View {
    let tssType: TssType
    let vault: Vault
    var isNewVault = false

    @State var navigationLinkActive = false
    @Environment(\.router) var router

    @State var animation: RiveViewModel?

    var body: some View {
        Screen {
            VStack {
                animation?.view()
                labels
                Spacer().frame(height: 100)
                PrimaryButton(title: "backupNow", leadingIcon: "square.and.arrow.down") {
                    navigationLinkActive = true
                }
            }
        }
        .onChange(of: navigationLinkActive) { _, isActive in
            guard isActive else { return }
            router.navigate(to: VaultRoute.backupPasswordOptions(
                tssType: tssType,
                backupType: .single(vault: vault),
                isNewVault: isNewVault
            ))
        }
        .onLoad {
            animation = RiveViewModel(fileName: "backupvault_splash", autoPlay: true)
        }
    }

    var labels: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("backupSetupTitle", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(NSLocalizedString("backupSetupSubtitle", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textExtraLight)
                .multilineTextAlignment(.center)

            Link(destination: StaticURL.VultBackupURL) {
                Text(NSLocalizedString("learnMore", comment: ""))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textLight)
                    .underline()
            }
        }
    }
}

#Preview {
    VaultBackupNowScreen(tssType: .Keygen, vault: Vault.example)
}
