//
//  VaultCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct VaultCellView<TrailingView: View>: View {
    let vault: Vault
    let isSelected: Bool
    @Binding var isEditing: Bool
    var trailingView: () -> TrailingView
    var action: () -> Void
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    init(
        vault: Vault,
        isSelected: Bool,
        isEditing: Binding<Bool>,
        trailingView: @escaping () -> TrailingView,
        action: @escaping () -> Void
    ) {
        self.vault = vault
        self.isSelected = isSelected
        self._isEditing = isEditing
        self.trailingView = trailingView
        self.action = action
    }
    
    init(
        vault: Vault,
        isSelected: Bool,
        isEditing: Binding<Bool>,
        action: @escaping () -> Void
    ) where TrailingView == EmptyView {
        self.vault = vault
        self.isSelected = isSelected
        self._isEditing = isEditing
        self.trailingView = { EmptyView() }
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VaultEditCellContainer(isEditing: $isEditing) {
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
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isEditing ? Theme.colors.textExtraLight : Theme.colors.borderLight))
                    trailingView()
                }
                .padding(12)
                .background(isSelected && !isEditing ? selectedBackground : nil)
            }
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
        VaultCellView(vault: .example, isSelected: false, isEditing: .constant(false)) {}
        
        VaultCellView(vault: .example, isSelected: true, isEditing: .constant(false)) {}
    }
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
}
