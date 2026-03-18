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

    @ObservedObject var viewModel: VaultSelectedViewModel

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("vaults".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)

                    VStack(spacing: 0) {
                        ForEach(vaults) { vault in
                            Button {
                                viewModel.selectedVault = vault
                                dismiss()
                            } label: {
                                vaultRow(vault: vault)
                            }
                            GradientListSeparator()
                                .showIf(vault != vaults.last)
                        }
                    }
                    .background(Theme.colors.bgSurface1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .screenTitle("referral".localized)
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
        .background(isSelected(vault: vault) ? Theme.colors.bgSurface2 : Theme.colors.bgSurface1)
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
        vault == viewModel.selectedVault
    }
}
