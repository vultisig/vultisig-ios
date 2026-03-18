//
//  SettingSelectionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingSelectionCell: View {
    let title: String
    let isSelected: Bool
    var description: String? = nil
    let showSeparator: Bool

    init(title: String, isSelected: Bool, description: String? = nil, showSeparator: Bool = true) {
        self.title = title
        self.isSelected = isSelected
        self.description = description
        self.showSeparator = showSeparator
    }

    var body: some View {
        VStack(spacing: .zero) {
            HStack {
                content
                Spacer()
                chevron
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            GradientListSeparator()
                .showIf(showSeparator)
        }
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
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var chevron: some View {
        Image(systemName: "checkmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 6, height: 6)
            .padding(5)
            .foregroundColor(Theme.colors.textPrimary)
            .background(Circle().fill(Theme.colors.primaryAccent3))
            .showIf(isSelected)
    }

    private func getDescriptionBlock(_ value: String) -> some View {
        Text(value)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textSecondary)
    }
}

#Preview {
    VStack {
        SettingSelectionCell(title: "English (UK)", isSelected: true)
        SettingSelectionCell(title: "Deutsch", isSelected: false, description: "German ")
    }
}
