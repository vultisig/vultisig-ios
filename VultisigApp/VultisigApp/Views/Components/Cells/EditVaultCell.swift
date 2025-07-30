//
//  EditVaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI

struct EditVaultCell: View {
    let title: String
    let description: String
    let icon: String
    let assetIcon: String?
    var isDestructive: Bool = false
    
    init(
        title: String,
        description: String,
        icon: String = "",
        assetIcon: String? = nil,
        isDestructive: Bool = false
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.assetIcon = assetIcon
        self.isDestructive = isDestructive
    }
    
    var body: some View {
        HStack(spacing: 15) {
            image
            content
            Spacer()
            chevron
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var image: some View {
        iconImage
            .font(.body24MontserratMedium)
            .foregroundColor(isDestructive ? .destructive : .neutral200)
            .frame(width: 30)
    }
    
    var iconImage: some View {
        if let assetIcon {
            Image(assetIcon)
        } else {
            Image(systemName: icon)
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body14Menlo)
                .foregroundColor(isDestructive ? .destructive : .neutral0)
            
            Text(NSLocalizedString(description, comment: ""))
                .font(.body12Menlo)
                .foregroundColor(isDestructive ? .destructive : .neutral300)
        }
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.body20Menlo)
            .foregroundColor(isDestructive ? .destructive : .neutral0)
    }
}

#Preview {
    EditVaultCell(title: "backup", description: "backupVault", icon: "arrow.down.circle.fill")
}
