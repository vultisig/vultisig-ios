//
//  VaultSelectorView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultSelectorView: View {
    let vaultName: String
    let isFastVault: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VaultIconTypeView(isFastVault: isFastVault)
                Text(vaultName)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                    .lineLimit(1)
                Icon(
                    named: "chevron-down-small",
                    color: Theme.colors.textPrimary,
                    size: 16
                )
            }
            .containerStyle(padding: 12, radius: 99, bgColor: Theme.colors.bgSurface1)
        }
    }
}

#Preview {
    VaultSelectorView(vaultName: "Main Vault", isFastVault: false) {}
    VaultSelectorView(vaultName: "Main Vault", isFastVault: true) {}
    VaultSelectorView(vaultName: "Main Vault with loooooong name", isFastVault: true) {}
}
