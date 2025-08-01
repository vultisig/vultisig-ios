//
//  SettingSelectionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingSelectionCell: View {
    @Environment(\.theme) var theme
    let title: String
    let isSelected: Bool
    var description: String? = nil
    
    var body: some View {
        HStack {
            content
            Spacer()
            chevron
        }
        .padding(12)
        .frame(height: 64)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleBlock
            
            if let description {
                getDescriptionBlock(description)
            }
        }
    }
    
    var titleBlock: some View {
        Text(title)
            .font(theme.fonts.bodySRegular)
            .foregroundColor(.neutral0)
    }
    
    var chevron: some View {
        Image(systemName: "checkmark")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .offset(x: -5)
            .opacity(isSelected ? 1 : 0)
    }
    
    private func getDescriptionBlock(_ value: String) -> some View {
        Text(value)
            .font(theme.fonts.caption12)
            .foregroundColor(.neutral300)
    }
}

#Preview {
    VStack {
        SettingSelectionCell(title: "English (UK)", isSelected: true)
        SettingSelectionCell(title: "Deutsch", isSelected: false, description: "German ")
    }
}
