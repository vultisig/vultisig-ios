//
//  SettingCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingCell: View {
    let title: String
    let icon: String
    var selection: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            iconBlock
            titleBlock
            Spacer()
            
            if let selection {
                getSelectionBlock(selection)
            }
            
            chevron
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var iconBlock: some View {
        Image(systemName: icon)
            .font(.body20Menlo)
            .foregroundColor(.neutral0)
    }
    
    var titleBlock: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body14Menlo)
            .foregroundColor(.neutral0)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    func getSelectionBlock(_ value: String) -> some View {
        Text(value)
            .font(.body14Menlo)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    SettingCell(title: "language", icon: "globe")
}
