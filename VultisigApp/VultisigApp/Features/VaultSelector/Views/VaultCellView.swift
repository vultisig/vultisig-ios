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
    let showDragIndicator: Bool
    let showTrailingDetails: Bool
    var trailingView: () -> TrailingView
    var action: (() -> Void)?

    @EnvironmentObject var homeViewModel: HomeViewModel

    init(
        vault: Vault,
        isSelected: Bool,
        isEditing: Binding<Bool>,
        showDragIndicator: Bool = true,
        showTrailingDetails: Bool = true,
        trailingView: @escaping () -> TrailingView,
        action: (() -> Void)? = nil
    ) {
        self.vault = vault
        self.isSelected = isSelected
        self._isEditing = isEditing
        self.showDragIndicator = showDragIndicator
        self.showTrailingDetails = showTrailingDetails
        self.trailingView = trailingView
        self.action = action
    }

    init(
        vault: Vault,
        isSelected: Bool,
        isEditing: Binding<Bool>,
        showDragIndicator: Bool = true,
        showTrailingDetails: Bool = true,
        action: (() -> Void)? = nil
    ) where TrailingView == EmptyView {
        self.vault = vault
        self.isSelected = isSelected
        self._isEditing = isEditing
        self.showDragIndicator = showDragIndicator
        self.showTrailingDetails = showTrailingDetails
        self.trailingView = { EmptyView() }
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
        } else {
            content
        }
    }

    var content: some View {
        VaultEditCellContainer(isEditing: $isEditing, showDragIndicator: showDragIndicator) {
            HStack {
                VaultCellMainView(vault: vault)
                Spacer()
                Group {
                    Icon(named: "checkmark-2-small", color: Theme.colors.alertSuccess, size: 24)
                        .showIf(isSelected)
                    Text(vault.signerPartDescription)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.caption12)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(isEditing ? Theme.colors.textTertiary : Theme.colors.borderLight))
                        .fixedSize()
                }
                .showIf(showTrailingDetails && !isEditing)
                trailingView()
            }
            .padding(12)
            .background(isSelected && !isEditing ? selectedBackground : nil)
        }
        .contentShape(Rectangle())
    }

    var selectedBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.colors.bgSurface1)
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
