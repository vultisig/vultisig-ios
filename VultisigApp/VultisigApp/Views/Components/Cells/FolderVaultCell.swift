//
//  FolderVaultCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import SwiftUI

struct FolderVaultCell: View {
    let title: String
    
    @State var isSelected = false
    
    var body: some View {
        content
            .onTapGesture {
                isSelected.toggle()
            }
    }
    
    var content: some View {
        HStack {
            text
            Spacer()
            toggle
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var text: some View {
        Text(title)
            .foregroundColor(.neutral0)
            .font(.body14MontserratBold)
    }
    
    var toggle: some View {
        Toggle("Is selected", isOn: $isSelected)
            .labelsHidden()
            .scaleEffect(0.8)
    }
}

#Preview {
    FolderVaultCell(title: "Main Vault")
}
