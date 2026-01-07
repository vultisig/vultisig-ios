//
//  VaultPairView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

import SwiftUI

struct VaultPartView: View {
    let vault: Vault
    
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VaultIconTypeView(isFastVault: vault.isFastVault)
            Text(vault.signerPartDescription)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(99)
        .overlay(
            RoundedRectangle(cornerRadius: 99)
                .inset(by: 1)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
}

