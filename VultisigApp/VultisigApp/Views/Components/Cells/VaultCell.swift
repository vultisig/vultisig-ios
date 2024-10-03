//
//  VaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct VaultCell: View {
    let vault: Vault
    let isEditing: Bool
    
    @StateObject var viewModel = VaultCellViewModel()
    
    var body: some View {
        HStack(spacing: 4) {
            rearrange
            title
            
            if viewModel.isFastVault {
                fastVaultLabel
            }
            
            Spacer()
            partAssignedCell
            actions
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditing)
        .onAppear {
            setData()
        }
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }
    
    var title: some View {
        Text(vault.name.capitalized)
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
    
    var actions: some View {
        HStack(spacing: 8) {
            selectOption
        }
    }
    
    var partAssignedCell: some View {
        Text("Part \(viewModel.order)of\(viewModel.totalSigners)")
            .font(.body14Menlo)
            .foregroundColor(.body)
    }
    
    var fastVaultLabel: some View {
        Text(NSLocalizedString("fastModeTitle", comment: "").capitalized)
            .font(.body14Menlo)
            .foregroundColor(.body)
            .padding(4)
            .padding(.horizontal, 2)
            .background(Color.blue200)
            .cornerRadius(5)
            .lineLimit(1)
    }
    
    var selectOption: some View {
        Image(systemName: "chevron.right")
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
    }
    
    private func setData() {
        viewModel.setupCell(vault)
    }
}

#Preview {
    VStack {
        VaultCell(vault: Vault.example, isEditing: true)
        VaultCell(vault: Vault.fastVaultExample, isEditing: false)
    }
}
