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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                title
                description
                    .showIf(isExpanded)
            }
            Spacer()
            chevron
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    var title: some View {
        Text(NSLocalizedString(question, comment: "Question"))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textSecondary)
    }

    var description: some View {
        Text(NSLocalizedString(answer, comment: "Answer"))
            .font(Theme.fonts.footnote)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var chevron: some View {
        Icon(
            named: "chevron-down",
            color: Theme.colors.textTertiary,
            size: 16
        )
        .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }
}

#Preview {
    SettingFAQCell(question: "vaultSecurityFAQQuestion", answer: "setupVaultFAQQuestion")
}
