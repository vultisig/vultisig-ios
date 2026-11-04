//
//  VaultBackupSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 27/08/2025.
//

import SwiftData
import SwiftUI

enum VaultBackupType: Hashable {
    case single(vault: Vault)
    case multiple(vaults: [Vault], selectedVault: Vault)

    var vault: Vault {
        switch self {
        case .single(let vault):
            return vault
        case .multiple(_, let selectedVault):
            return selectedVault
        }
    }

    func markBackedUp() {
        switch self {
        case .single(vault: let vault):
            vault.isBackedUp = true
        case .multiple(let vaults, let selectedVault):
            selectedVault.isBackedUp = true
            vaults.forEach { $0.isBackedUp = true }
        }
    }
}

struct VaultBackupSelectionScreen: View {
    @Query var vaults: [Vault]

    @Environment(\.router) var router

    let selectedVault: Vault
    var origin: VaultBackupOrigin = .standard

    var vaultsToShow: Int { 5 }
    var moreVaultsCount: Int { vaults.count - vaultsToShow }

    var body: some View {
        Screen {
            ScrollView {
                VStack(spacing: 36) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("selectVaultsToBackUpTitle".localized)
                            .font(Theme.fonts.title1)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Text("selectVaultsToBackUpSubtitle".localized)
                            .settingsText(.bodyS)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                    VStack(spacing: 16) {
                        backupTypeContainer(type: .single(vault: selectedVault))
                        backupTypeContainer(type: .multiple(vaults: vaults, selectedVault: selectedVault))
                    }
                }
            }
        }
    }

    func backupTypeContainer(type: VaultBackupType) -> some View {
        Button {
            router.navigate(to: VaultRoute.backupPasswordOptions(
                tssType: .Keygen,
                backupType: type,
                isNewVault: false,
                origin: origin
            ))
        } label: {
            backupTypeRow(type: type)
        }
    }

    func backupTypeRow(type: VaultBackupType) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title(for: type))
                    .settingsText(.bodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Icon(.chevronRightSmall, color: Theme.colors.textSecondary, size: 16)
            }
            switch type {
            case .single(let vault):
                vaultRow(vault: vault)
                    .background(Theme.colors.bgSurface1)
                    .clipShape(Theme.radius.md.shape)
            case .multiple(let vaults, _):
                VStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(vaults.prefix(vaultsToShow)) { vault in
                            vaultRow(vault: vault)
                            Rectangle()
                                .fill(Theme.colors.borderLight)
                                .frame(height: 1)
                                .showIf(vault != vaults.last)
                        }
                    }
                    .background(Theme.colors.bgSurface1)
                    .clipShape(Theme.radius.md.shape)

                    Text(String(format: "plusMore".localized, moreVaultsCount))
                        .settingsText(.footnote)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .showIf(moreVaultsCount > 0)
                }
            }
        }
        .padding(15)
        .overlay(Theme.radius.xl.shape.strokeBorder(Theme.colors.borderLight, lineWidth: 1))
    }

    func vaultRow(vault: Vault) -> some View {
        HStack {
            Text(vault.name)
                .settingsText(.bodyS)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()

            VaultPartView(vault: vault, usesFilledIcon: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }

    func title(for type: VaultBackupType) -> String {
        switch type {
        case .single:
            return "thisVaultOnly".localized
        case .multiple:
            return "allVaults".localized
        }
    }
}
