//
//  SettingSelectionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

/// How a selection row draws its text and selected state.
enum SettingSelectionCellStyle {
    case standard
    /// A row at least 65 tall that fills when selected and marks it with a check.
    case highlighted(title: SettingsTextStyle)
    /// A row with a radio that always shows.
    case radio
}

struct SettingSelectionCell: View {
    let title: String
    let isSelected: Bool
    var description: String? = nil
    let style: SettingSelectionCellStyle

    private static let highlightedMinHeight: CGFloat = 65

    init(title: String, isSelected: Bool, description: String? = nil, style: SettingSelectionCellStyle = .standard) {
        self.title = title
        self.isSelected = isSelected
        self.description = description
        self.style = style
    }

    var body: some View {
        switch style {
        case .standard:
            HStack {
                content
                Spacer()
                chevron
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        case .highlighted(let titleStyle):
            HStack(spacing: 12) {
                settingsContent(titleStyle: titleStyle)
                checkmark
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: Self.highlightedMinHeight)
            .background(isSelected ? Theme.colors.bgSurface12 : Theme.colors.bgSurface1)
            .contentShape(Rectangle())
        case .radio:
            HStack(spacing: 14) {
                settingsContent(titleStyle: .bodyM)
                radio
            }
            .padding(14)
            .contentShape(Rectangle())
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
            .font(Theme.fonts.subtitle)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    var chevron: some View {
        Image(systemName: "checkmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 6, height: 6)
            .padding(5)
            .foregroundStyle(Theme.colors.textPrimary)
            .background(Circle().fill(Theme.colors.primaryAccent3))
            // Hidden rather than removed, so selecting a row never reflows its text.
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(!isSelected)
    }

    private func getDescriptionBlock(_ value: String) -> some View {
        Text(value)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textSecondary)
    }

    private func settingsContent(titleStyle: SettingsTextStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .settingsText(titleStyle)
                .foregroundStyle(Theme.colors.textPrimary)

            if let description {
                Text(description)
                    .settingsText(.caption)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var checkmark: some View {
        Icon(.selectionCheck, color: Theme.colors.textPrimary, size: 16)
            .background(Circle().fill(Theme.colors.primaryAccent3))
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(!isSelected)
    }

    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Theme.colors.primaryAccent4 : Theme.colors.borderNormal,
                    lineWidth: isSelected ? 1.5 : 1
                )
            Circle()
                .fill(Theme.colors.primaryAccent4)
                .frame(width: 12, height: 12)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(!isSelected)
    }
}

#Preview {
    VStack {
        SettingSelectionCell(title: "English (UK)", isSelected: true)
        SettingSelectionCell(title: "Deutsch", isSelected: false, description: "German ")
    }
}
