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
    var isDestructive: Bool = false
    
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
        Image(systemName: icon)
            .font(.body24MontserratMedium)
            .foregroundColor(isDestructive ? .destructive : .neutral200)
            .frame(width: 30)
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
