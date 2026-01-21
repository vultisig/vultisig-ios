//
//  BackupNowDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-05.
//

import SwiftUI

struct BackupNowDisclaimer: View {
    let vault: Vault

    @Environment(\.router) var router

    var body: some View {
        Button {
            router.navigate(to: VaultRoute.backupPasswordOptions(
                tssType: .Keygen,
                backupType: .single(vault: vault),
                isNewVault: false
            ))
        } label: {
            container
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(1)
        }.buttonStyle(.plain)
    }

    var content: some View {
        ZStack {
            title
            components
        }
        .frame(height: 76)
        .padding(.horizontal, 12)
        .background(Theme.colors.alertError.opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.alertError, lineWidth: 1)
        )
    }

    var components: some View {
        HStack {
            icon
            Spacer()
            chevron
        }
    }

    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(Theme.fonts.title2)
            .foregroundColor(Theme.colors.alertError)
    }

    var title: some View {
        Text(NSLocalizedString("backupYourVaultNow", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
    }
}

#Preview {
    BackupNowDisclaimer(vault: Vault.example)
}
