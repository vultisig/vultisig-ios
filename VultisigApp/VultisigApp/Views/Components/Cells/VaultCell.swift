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
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditing)
        .onAppear {
            setData()
        }
    }

    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }

    var title: some View {
        Text(vault.name.capitalized)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }

    var actions: some View {
        selectOption
    }

    var partAssignedCell: some View {
        Group {
            Text(NSLocalizedString("share", comment: "")) +
            Text(" \(viewModel.order)") +
            Text(NSLocalizedString("of", comment: "")) +
            Text("\(viewModel.totalSigners)")
        }
        .font(Theme.fonts.bodySRegular)
        .foregroundColor(Theme.colors.textSecondary)
    }

    var fastVaultLabel: some View {
        Text(NSLocalizedString("fastModeTitle", comment: "").capitalized)
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textSecondary)
            .padding(4)
            .padding(.horizontal, 2)
            .background(Theme.colors.border)
            .cornerRadius(5)
            .lineLimit(1)
    }

    var selectOption: some View {
        Image(systemName: "chevron.right")
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: isEditing ? 0 : nil)
            .clipped()
    }

    private func setData() {
        viewModel.setupCell(vault)
    }
}

#Preview {
    VStack {
        VaultCell(vault: Vault.example, isEditing: true)
        VaultCell(vault: Vault.example, isEditing: true)
        VaultCell(vault: Vault.fastVaultExample, isEditing: false)
    }
}
