//
//  FolderVaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import SwiftUI

struct FolderVaultCell: View {
    let vault: Vault
    @Binding var selectedVaults: [Vault]

    @State var isSelected: Bool = false

    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onTapGesture {
                isSelected.toggle()
            }
            .onChange(of: isSelected) { _, _ in
                handleSelection()
            }
    }

    var content: some View {
        HStack {
            text
            Spacer()
            toggle
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }

    var text: some View {
        Text(vault.name)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
    }

    var toggle: some View {
        VultiToggle(isOn: $isSelected)
    }

    private func setData() {
        if selectedVaults.contains(vault) {
            isSelected = true
        }
    }

    private func handleSelection() {
        if isSelected {
            selectedVaults.append(vault)
        } else {
            removeVault(vault)
        }
    }

    private func removeVault(_ vault: Vault) {
        for index in 0..<selectedVaults.count {
            if areVaultsSame(selectedVaults[index], vault) {
                selectedVaults.remove(at: index)
                return
            }
        }
    }

    private func areVaultsSame(_ selectedVault: Vault, _ vault: Vault) -> Bool {
        selectedVault.name == vault.name && selectedVault.pubKeyECDSA == vault.pubKeyECDSA && selectedVault.pubKeyEdDSA == vault.pubKeyEdDSA
    }
}

#Preview {
    FolderVaultCell(vault: Vault.example, selectedVaults: .constant([]))
}
