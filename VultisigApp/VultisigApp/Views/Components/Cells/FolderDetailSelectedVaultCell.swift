//
//  FolderDetailSelectedVaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

import SwiftUI
// TODO: - To remove

struct FolderDetailSelectedVaultCell: View {
    
    
    let vault: Vault
    let isEditing: Bool
    let handleVaultSelection: (Vault) -> ()
    
    @StateObject var viewModel = FolderDetailCellViewModel()
    
    var body: some View {
        ZStack {
            if isEditing {
                content
            } else {
                button
            }
        }
        .animation(.easeInOut, value: isEditing)
        .onAppear {
            setData()
        }
    }
    
    var button: some View {
        Button {
            handleVaultSelection(vault)
        } label: {
            content
        }
    }
    
    var content: some View {
        HStack {
            rearrange
            text
            
            if viewModel.isFastVault {
                fastVaultLabel
            }
            
            Spacer()
            partAssignedCell
            
            action
        }
        .padding(12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(10)
    }
    
    var action: some View {
        Button {
            handleVaultSelection(vault)
        } label: {
            ZStack {
                if isEditing {
                    toggle
                } else {
                    chevron
                }
            }
        }
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }
    
    var text: some View {
        Text(vault.name)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
    }
    
    var toggle: some View {
        Toggle("Is selected", isOn: .constant(true))
            .labelsHidden()
            .scaleEffect(0.8)
            .allowsHitTesting(false)
    }
    
    var partAssignedCell: some View {
        Text("Share \(viewModel.order)of\(viewModel.totalSigners)")
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textLight)
    }
    
    var fastVaultLabel: some View {
        Text(NSLocalizedString("fastModeTitle", comment: "").capitalized)
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textLight)
            .padding(4)
            .padding(.horizontal, 2)
            .background(Theme.colors.border)
            .cornerRadius(5)
            .lineLimit(1)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: isEditing ? 0 : nil)
            .padding(.vertical, 8)
    }
    
    func setData() {
        viewModel.assignSigners(vault)
        viewModel.setupLabel(vault)
    }
}

//#Preview {
//    VStack {
//        FolderDetailSelectedVaultCell(vault: Vault.example, isEditing: false, handleVaultSelection: <#(Vault) -> ()#>)
//        FolderDetailSelectedVaultCell(vault: Vault.example, isEditing: true)
//    }
//}
