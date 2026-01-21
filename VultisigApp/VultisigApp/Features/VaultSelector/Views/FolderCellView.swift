//
//  FolderCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct FolderCellView: View {
    let folder: Folder
    let selectedVaultName: String?
    @Binding var isEditing: Bool
    let action: () -> Void

    var isSelected: Bool {
        folder.containedVaultNames.contains(selectedVaultName ?? "")
    }

    var body: some View {
        Button(action: action) {
            VaultEditCellContainer(isEditing: $isEditing, showDragIndicator: true) {
                HStack {
                    Icon(named: isSelected ? "folder-fill" : "folder", color: Theme.colors.alertInfo, size: 16)
                        .padding(12)
                        .background(Circle().fill(Theme.colors.bgSurface2))
                        .overlay(
                            Circle()
                                .inset(by: 0.5)
                                .stroke(Theme.colors.borderLight, lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.folderName)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodySMedium)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)

                        if isSelected {
                            selectedSubtitle
                        } else {
                            nonSelectedSubtitle
                        }
                    }

                    Spacer()

                    Icon(
                        named: "chevron-right-small",
                        color: Theme.colors.textPrimary,
                        size: 16
                    )
                    .opacity(isEditing ? 0 : 1)
                }
                .padding(12)
                .background(isSelected && !isEditing ? selectedBackground : nil)
            }
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    var nonSelectedSubtitle: some View {
        let vaultsText: String = folder.containedVaultNames.count > 1 ? "vaults".localized : "vault".localized
        let subtitle = "\(folder.containedVaultNames.count) \(vaultsText)"

        Text(subtitle)
            .foregroundStyle(Theme.colors.textSecondary)
            .font(Theme.fonts.footnote)
    }

    var selectedSubtitle: some View {
        HStack(spacing: 4) {
            Icon(
                named: "checkmark-2-small",
                color: Theme.colors.alertInfo,
                size: 16
            )

            Text("\(selectedVaultName ?? "") \("active".localized)")
                .foregroundStyle(Theme.colors.alertInfo)
                .font(Theme.fonts.footnote)
        }
    }

    var selectedBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.colors.bgSurface1)
    }
}

#Preview {
    FolderCellView(
        folder: .example,
        selectedVaultName: "",
        isEditing: .constant(false),
        action: {}
    )
}
