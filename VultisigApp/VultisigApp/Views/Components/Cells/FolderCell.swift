//
//  FolderCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

import SwiftUI

struct FolderCell: View {
    let folder: Folder
    let isEditing: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            rearrange
            folderIcon
            title
            Spacer()
            chevron
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditing)
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }
    
    var folderIcon: some View {
        Image(systemName: "folder")
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var title: some View {
        Text(folder.folderName.capitalized)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: isEditing ? 0 : nil)
            .clipped()
    }
}

#Preview {
    VStack {
        FolderCell(folder: Folder.example, isEditing: true)
        FolderCell(folder: Folder.example, isEditing: false)
    }
}
