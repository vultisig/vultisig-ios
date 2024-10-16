//
//  VaultPairDetailCell.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//

import Foundation

import SwiftUI

struct VaultPairDetailCell: View {
    let title: String
    let description: String
    var isBold: Bool = false
    
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
            if !title.isEmpty {
                Text(NSLocalizedString(title, comment: ""))
                    .font(isBold ? .body20MenloBold : .body16MenloBold)
                    .foregroundColor( .neutral0)
            }
            
            if !description.isEmpty {
                Text(NSLocalizedString(description, comment: ""))
                    .font(isBold ? .body16Menlo : .body12Menlo)
                    .foregroundColor(.neutral0)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .opacity(0.8)
            }
        }
    }
}

#Preview {
    VaultPairDetailCell(title: "backup", description: "backupVault")
}
