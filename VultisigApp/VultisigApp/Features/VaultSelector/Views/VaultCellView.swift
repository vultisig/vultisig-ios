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
    let rightDragIndicator: Bool
    let showTrailingDetails: Bool
    var trailingView: () -> TrailingView
    var action: () -> Void
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    init(
        vault: Vault,
        isSelected: Bool,
        isEditing: Binding<Bool>,
        rightDragIndicator: Bool = true,
        showTrailingDetails: Bool = true,
        trailingView: @escaping () -> TrailingView,
        action: @escaping () -> Void
    ) {
        self.vault = vault
        self.isSelected = isSelected
        self._isEditing = isEditing
        self.rightDragIndicator = rightDragIndicator
        self.showTrailingDetails = showTrailingDetails
        self.trailingView = trailingView
        self.action = action
    }
    
    init(
        vault: Vault,
        isSelected: Bool,
        isEditing: Binding<Bool>,
        rightDragIndicator: Bool = true,
        showTrailingDetails: Bool = true,
        action: @escaping () -> Void
    ) where TrailingView == EmptyView {
        self.vault = vault
        self.isSelected = isSelected
        self._isEditing = isEditing
        self.rightDragIndicator = rightDragIndicator
        self.showTrailingDetails = showTrailingDetails
        self.trailingView = { EmptyView() }
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VaultEditCellContainer(isEditing: $isEditing, rightDragIndicator: rightDragIndicator) {
                HStack {
                    VaultCellMainView(vault: vault)
                    Spacer()
                    Group {
                        Icon(named: "checkmark-2-small", color: Theme.colors.alertSuccess, size: 24)
                            .showIf(isSelected)
                        Text(vault.signerPartDescription)
                            .foregroundStyle(Theme.colors.textExtraLight)
                            .font(Theme.fonts.caption12)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8).stroke(isEditing ? Theme.colors.textExtraLight : Theme.colors.borderLight))
                            .fixedSize()
                    }
                    .showIf(showTrailingDetails)
                    trailingView()
                }
                .padding(8)
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
