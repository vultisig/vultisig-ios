//
//  AddFolderVaultCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct AddFolderVaultCellView: View {
    let vault: Vault
    let isSelected: Bool
    var onSelection: (Bool) -> Void
    @State var isSelectedInternal: Bool = false

    var body: some View {
        HStack {
            VaultCellMainView(vault: vault)
                .opacity(isSelectedInternal ? 1 : 0.5)
                .animation(.interpolatingSpring, value: isSelectedInternal)
            Spacer()
            Toggle("", isOn: $isSelectedInternal)
                .labelsHidden()
                .scaleEffect(0.8)
                .tint(Theme.colors.primaryAccent4)
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSurface1)
        .onLoad {
            isSelectedInternal = isSelected
        }
        .onChange(of: isSelectedInternal) {
            guard isSelectedInternal != isSelected else {
                return
            }

            // Wait for toggle animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelection(isSelectedInternal)
            }
        }
    }
}
