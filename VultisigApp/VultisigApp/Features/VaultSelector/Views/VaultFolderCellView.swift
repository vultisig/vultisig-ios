//
//  VaultFolderCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI

struct VaultFolderCellView: View {
    let vault: Vault
    let isOnFolder: Bool
    let isSelected: Bool
    var onSelection: () -> Void

    @State var isOnFolderInternal: Bool = false

    var body: some View {
        VaultCellView(
            vault: vault,
            isSelected: isSelected,
            isEditing: .constant(true),
            showDragIndicator: isOnFolder,
            showTrailingDetails: false,
            trailingView: {
                VultiToggle(isOn: $isOnFolderInternal)
            }
        )
        .background(Theme.colors.bgPrimary)
        .onLoad {
            isOnFolderInternal = isOnFolder
        }
        .onChange(of: isOnFolderInternal) {
            guard isOnFolderInternal != isOnFolder else {
                return
            }

            // Wait for toggle animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelection()
            }
        }
    }
}

#Preview {
    VaultFolderCellView(
        vault: .example,
        isOnFolder: true,
        isSelected: false
    ) {}
}
