//
//  VaultCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct VaultCellView: View {
    let vault: Vault
    let isSelected: Bool
    var action: () -> Void
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        Button(action: action) {
            HStack {
                VaultIconTypeView(isFastVault: vault.isFastVault)
                    .padding(12)
                    .background(Circle().fill(Theme.colors.bgTertiary))
                    .overlay(
                        Circle()
                            .inset(by: 0.5)
                            .stroke(Theme.colors.borderLight, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(vault.name)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                    
                    Text(homeViewModel.balanceText(for: vault))
                        .foregroundStyle(Theme.colors.textLight)
                        .font(Theme.fonts.priceFootnote)
                }
                
                Spacer()
                
                Icon(named: "checkmark-2-small", color: Theme.colors.alertSuccess, size: 24)
                    .showIf(isSelected)
                Text(vault.signerPartDescription)
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .font(Theme.fonts.caption12)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.colors.borderLight))
            }
            .padding(12)
            .background(isSelected ? selectedBackground : nil)
            .contentShape(Rectangle())
        }
    }
    
    var selectedBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.colors.bgSecondary)
    }
}

#Preview {
    VStack {
        VaultCellView(vault: .example, isSelected: false) {}
        
        VaultCellView(vault: .example, isSelected: true) {}
    }
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
}
