//
//  FolderDetailremainingVaultsCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

import SwiftUI

struct FolderDetailremainingVaultsCell: View {
    let vault: Vault
    
    var body: some View {
        content
    }
    
    var content: some View {
        HStack {
            text
            Spacer()
            toggle
        }
        .padding(12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(10)
    }
    
    var text: some View {
        Text(vault.name)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
    }
    
    var toggle: some View {
        Toggle("Is selected", isOn: .constant(false))
            .labelsHidden()
            .scaleEffect(0.8)
            .allowsHitTesting(false)
    }
}

#Preview {
    FolderDetailremainingVaultsCell(vault: Vault.example)
}
