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

