//
//  ActionBannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct ActionBannerView: View {
    let icon: ImageResource?
    let title: String
    let subtitle: String
    let buttonTitle: String
    let buttonIcon: ImageResource?
    let showsActionButton: Bool
    let action: () -> Void

    init(
        icon: ImageResource? = nil,
        title: String,
        subtitle: String,
        buttonTitle: String,
        buttonIcon: ImageResource? = nil,
        showsActionButton: Bool = true,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.buttonIcon = buttonIcon
        self.showsActionButton = showsActionButton
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            GradientListSeparator()
            VStack(spacing: 12) {
                Icon(icon ?? .circleDashed, color: Theme.colors.primaryAccent4, size: 24)
                VStack(spacing: 8) {
                    Text(title)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.subtitle)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.footnote)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 263)

                Group {
                    if let buttonIcon {
                        PrimaryButton(title: buttonTitle, leadingIcon: buttonIcon, size: .mini, action: action)
                    } else {
                        PrimaryButton(title: buttonTitle, size: .mini, action: action)
                    }
                }
                    .fixedSize()
                    .showIf(showsActionButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))
        }
        .clipShape(
            .rect(
                topLeadingRadius: Theme.radius.xl.points,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Theme.radius.xl.points,
                // Only the top corners are rounded, so this cannot use the
                // token's `shape` and the style has to be carried across by
                // hand — otherwise the docked banner would keep the SDK's
                // default while everything else follows the token.
                style: Theme.radius.xl.style
            )
        )
    }
}

#Preview {
    ActionBannerView(
        title: "Test",
        subtitle: "This is a test",
        buttonTitle: "Retry",
        action: {}
    )
}
