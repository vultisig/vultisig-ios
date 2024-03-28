//
//  VaultCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct VaultCell: View {
    let vault: Vault
    
    var body: some View {
        HStack(spacing: 12) {
            title
            Spacer()
            actions
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var title: some View {
        Text(vault.name.capitalized)
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
    }
    
    var actions: some View {
        HStack(spacing: 8) {
            editOption
            selectOption
        }
    }
    
    var editOption: some View {
        NavigationLink {
            EditVaultView(vault: vault)
        } label: {
            editImage
        }
    }
    
    var editImage: some View {
        Image(systemName: "square.and.pencil")
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
            .offset(y: -2)
            .frame(width: 48, height: 48)
    }
    
    var selectOption: some View {
        Image(systemName: "chevron.right")
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
    }
}

#Preview {
    VaultCell(vault: Vault.example)
}
