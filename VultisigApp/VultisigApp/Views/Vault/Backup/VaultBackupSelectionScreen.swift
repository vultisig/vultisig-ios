//
//  VaultBackupSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 27/08/2025.
//

import SwiftData
import SwiftUI

enum VaultBackupType {
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
        case .single(let vault):
            vault.isBackedUp = true
        case .multiple(let vaults, let selectedVault):
            selectedVault.isBackedUp = true
            vaults.forEach { $0.isBackedUp = true }
        }
    }
}

struct VaultBackupSelectionScreen: View {
    @Query var vaults: [Vault]
    
    let selectedVault: Vault
    
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
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textExtraLight)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 16) {
                        backupTypeContainer(type: .single(vault: selectedVault))
                        backupTypeContainer(type: .multiple(vaults: vaults, selectedVault: selectedVault))
                    }
                }
            }
        }
    }
    
    func backupTypeContainer(type: VaultBackupType) -> some View {
        NavigationLink {
            VaultBackupPasswordOptionsScreen(tssType: .Keygen, backupType: type)
        } label: {
            backupTypeRow(type: type)
        }
    }
    
    func backupTypeRow(type: VaultBackupType) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title(for: type))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
                Spacer()
                Icon(named: "chevron-right", color: Theme.colors.textExtraLight)
            }
            switch type {
            case .single(let vault):
                vaultRow(vault: vault)
                    .background(Theme.colors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .multiple(let vaults, _):
                VStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(vaults.prefix(vaultsToShow)) { vault in
                            vaultRow(vault: vault)
                            GradientListSeparator()
                                .showIf(vault != vaults.last)
                        }
                    }
                    .background(Theme.colors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Text(String(format: "plusMore".localized, moreVaultsCount))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .showIf(moreVaultsCount > 0)
                }
            }
        }
        .containerStyle(padding: 12)
    }
    
    func vaultRow(vault: Vault) -> some View {
        HStack {
            Text(vault.name)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            
            VaultPartView(vault: vault)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
