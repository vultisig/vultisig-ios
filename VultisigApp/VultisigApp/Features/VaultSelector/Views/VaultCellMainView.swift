//
//  VaultCellMainView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct VaultCellMainView: View {
    let vault: Vault
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            VaultIconTypeView(isFastVault: vault.isFastVault)
                .padding(12)
                .background(Circle().fill(Theme.colors.bgSurface2))
                .overlay(
                    Circle()
                        .inset(by: 0.5)
                        .stroke(Theme.colors.borderLight, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(vault.name)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
                    .lineLimit(1)
                
                Text(homeViewModel.balanceText(for: vault))
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.priceFootnote)
            }
        }
    }
}

#Preview {
    VaultCellMainView(vault: .example)
        .environmentObject(HomeViewModel())
}
