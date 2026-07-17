//
//  InfoTooltip.swift
//  VultisigApp
//

import SwiftUI

struct InfoTooltip: View {
    let title: String
    let description: String
    var arrowDirection: TooltipArrowDirection = .up
    var arrowXFraction: CGFloat = 0.5
    var maxWidth: CGFloat = 220
    let onDismiss: () -> Void

    private var topPadding: CGFloat {
        arrowDirection == .up ? 24 : 12
    }

    private var bottomPadding: CGFloat {
        arrowDirection == .up ? 12 : 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textDark)

                Spacer()

                Button(action: onDismiss) {
                    Icon(.x, color: Theme.colors.textButtonDisabled, size: 20)
                }
            }

            Text(description)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(Theme.colors.bgTooltip)
        .clipShape(TooltipShape(
            arrowXFraction: arrowXFraction,
            arrowDirection: arrowDirection
        ))
        .frame(maxWidth: maxWidth)
    }
}

#Preview {
    VStack(spacing: 40) {
        InfoTooltip(
            title: "Rewards",
            description: "Rewards are automatically credited to your balance.",
            arrowDirection: .up,
            onDismiss: {}
        )

        InfoTooltip(
            title: "Rewards",
            description: "Rewards are automatically credited to your balance.",
            arrowDirection: .down,
            onDismiss: {}
        )
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
