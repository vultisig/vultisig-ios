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
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }

    var iconBlock: some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodyLRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var titleBlock: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }

    func getSelectionBlock(_ value: String) -> some View {
        Text(value)
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }
}

#Preview {
    SettingCell(title: "language", icon: "globe")
}
