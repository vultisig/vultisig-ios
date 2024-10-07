//
//  FolderCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

import SwiftUI

struct FolderCell: View {
    let folder: VaultFolder
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
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditing)
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditing ? nil : 0)
            .clipped()
    }
    
    var folderIcon: some View {
        Image(systemName: "folder")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
    }
    
    var title: some View {
        Text(folder.folderName.capitalized)
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.body16MontserratBold)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditing ? 0 : nil)
            .clipped()
    }
}

#Preview {
    VStack {
        FolderCell(folder: VaultFolder.example, isEditing: true)
        FolderCell(folder: VaultFolder.example, isEditing: false)
    }
}
