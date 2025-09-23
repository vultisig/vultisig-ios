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
            isEditing: .constant(false),
            trailingView: {
                Toggle("", isOn: $isOnFolderInternal)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .tint(Theme.colors.primaryAccent4)
            },
            action: {}
        )
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
