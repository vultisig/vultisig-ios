//
//  VaultPairDetailCell.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//

import Foundation

import SwiftUI

struct VaultPairDetailCell: View {
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 15) {
            content
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body16MenloBold)
                .foregroundColor( .neutral0)
            
            Text(NSLocalizedString(description, comment: ""))
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
            
        }
    }
}

#Preview {
    EditVaultCell(title: "backup", description: "backupVault", icon: "arrow.down.circle.fill")
}
