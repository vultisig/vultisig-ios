//
//  SettingFAQCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingFAQCell: View {

    let question: String
    let answer: String

    @State var isExpanded = false

    private static let collapsedMinHeight: CGFloat = 70

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                title
                description
                    .showIf(isExpanded)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            chevron
        }
        .padding(.horizontal, 20)
        // A two-line question fits the 70 tall row only with 15 above and below.
        .padding(.vertical, isExpanded ? 16 : 15)
        .frame(minHeight: Self.collapsedMinHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    var title: some View {
        Text(NSLocalizedString(question, comment: "Question"))
            .settingsText(.bodyS)
            .foregroundStyle(Theme.colors.textSecondary)
    }

    var description: some View {
        Text(NSLocalizedString(answer, comment: "Answer"))
            .settingsText(.footnote)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    var chevron: some View {
        Icon(
            .chevronDownSmall,
            color: Theme.colors.textTertiary,
            size: 16
        )
        .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }
}

#Preview {
    SettingFAQCell(question: "vaultSecurityFAQQuestion", answer: "setupVaultFAQQuestion")
}
