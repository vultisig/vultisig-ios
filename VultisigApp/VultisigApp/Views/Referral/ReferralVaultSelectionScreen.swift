//
//  ReferralVaultSelectionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

import SwiftData
import SwiftUI

struct ReferralVaultSelectionScreen: View {
    @Query var vaults: [Vault]
    @Environment(\.dismiss) var dismiss
    
    @Binding var selectedVault: Vault?
    
    var body: some View {
        Screen(title: "referral".localized) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("vaults".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textExtraLight)
                    
                    VStack(spacing: 0) {
                        ForEach(vaults) { vault in
                            Button {
                                selectedVault = vault
                                dismiss()
                            } label: {
                                vaultRow(vault: vault)
                            }
                            GradientListSeparator()
                                .showIf(vault != vaults.last)
                        }
                    }
                    .background(Theme.colors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    func vaultRow(vault: Vault) -> some View {
        HStack(spacing: 16) {
            Text(vault.name)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            HStack(spacing: 8) {
                VaultPartView(vault: vault)
                trailingIcon(vault: vault)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isSelected(vault: vault) ? Theme.colors.bgTertiary : Theme.colors.bgSecondary)
    }
    
    
    @ViewBuilder
    func trailingIcon(vault: Vault) -> some View {
        if isSelected(vault: vault) {
            Icon(named: "check", color: Theme.colors.alertSuccess, size: 16)
        } else {
            Icon(named: "chevron-right", color: Theme.colors.textPrimary, size: 16)
        }
    }
    
    func isSelected(vault: Vault) -> Bool {
        vault == selectedVault
    }
}

struct VaultPartView: View {
    let vault: Vault
    
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            image
                .frame(width: 16, height: 16)
            Text(partText)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(99)
        .overlay(
            RoundedRectangle(cornerRadius: 99)
                .inset(by: 1)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    var partText: String {
        guard let index = vault.signers.firstIndex(of: vault.localPartyID) else {
            return "-"
        }
        return String(format: "partOf".localized, index + 1, vault.signers.count)
    }

    @ViewBuilder
    var image: some View {
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
