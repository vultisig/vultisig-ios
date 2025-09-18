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
        let partText = vault.libType == .DKLS ? "partOf".localized : "shareOf".localized
        return String(format: partText, index + 1, vault.signers.count)
    }
}

