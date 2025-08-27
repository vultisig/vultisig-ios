//
//  VaultBackupSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 27/08/2025.
//

import SwiftData
import SwiftUI

enum VaultBackupType {
    case single(Vault)
    case multiple([Vault])
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
                        backupTypeContainer(type: .single(selectedVault))
                        backupTypeContainer(type: .multiple(vaults))
                    }
                }
            }
        }
    }
    
    func backupTypeContainer(type: VaultBackupType) -> some View {
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
            case .multiple(let vaults):
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
            
            HStack(alignment: .center, spacing: 4) {
                image(for: vault)
                    .frame(width: 16, height: 16)
                Text(partText(for: vault))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textExtraLight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .cornerRadius(99)
            .overlay(
                RoundedRectangle(cornerRadius: 99)
                    .inset(by: 1)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
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
    
    func partText(for vault: Vault) -> String {
        guard let index = vault.signers.firstIndex(of: vault.localPartyID) else {
            return "-"
        }
        return String(format: "partOf".localized, index + 1, vault.signers.count)
    }
    
    @ViewBuilder
    func image(for vault: Vault) -> some View {
        if vault.isFastVault {
            Image("lightning")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .foregroundStyle(Theme.colors.alertWarning)
        } else {
            Image("shield")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .foregroundStyle(Theme.colors.bgButtonPrimary)
        }
    }
}
