//
//  NetworkPromptCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct NetworkPromptCell: View {
    let network: NetworkPromptType
    let isSelected: Bool

    var body: some View {
        content
    }

    var phoneCell: some View {
        HStack(spacing: 8) {
            network.getImage()
                .font(Theme.fonts.bodySRegular)
                .foregroundColor(Theme.colors.bgButtonPrimary)

            Text(NSLocalizedString(network.rawValue, comment: ""))
                .font(Theme.fonts.caption10)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.colors.border : Theme.colors.bgSurface2)
        .cornerRadius(20)
        .padding(.horizontal, 8)
    }

    var padCell: some View {
        HStack(spacing: 8) {
            network.getImage()
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(Theme.colors.bgButtonPrimary)

            Text(NSLocalizedString(network.rawValue, comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? Theme.colors.border : Theme.colors.bgSurface2)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.colors.textPrimary, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        .padding(.horizontal, 8)
    }
}

#Preview {
    NetworkPromptCell(network: .Internet, isSelected: true)
}
