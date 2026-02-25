//
//  OnboardingInformationRowView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI

struct OnboardingInformationRowView: View {
    let title: String
    let subtitle: String
    let icon: String
    var highlightedText: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Icon(
                named: icon,
                color: Theme.colors.alertInfo,
                size: 24
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)

                if let highlightedText {
                    HighlightedText(
                        text: subtitle,
                        highlightedText: highlightedText,
                        textStyle: {
                            $0.font = Theme.fonts.footnote
                            $0.foregroundColor = Theme.colors.textTertiary
                        },
                        highlightedTextStyle: {
                            $0.foregroundColor = Theme.colors.textPrimary
                        }
                    )
                } else {
                    Text(subtitle)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.footnote)
                }
            }
        }
    }
}

#Preview {
    OnboardingInformationRowView(
        title: "atLeastOneDevice".localized,
        subtitle: "atLeastOneDeviceSubtitle".localized,
        icon: "devices"
    )
}
