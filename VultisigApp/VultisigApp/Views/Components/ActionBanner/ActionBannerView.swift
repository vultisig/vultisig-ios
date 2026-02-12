//
//  ActionBannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct ActionBannerView: View {
    let icon: String?
    let title: String
    let subtitle: String
    let buttonTitle: String
    let buttonIcon: String?
    let showsActionButton: Bool
    let action: () -> Void

    init(
        icon: String? = nil,
        title: String,
        subtitle: String,
        buttonTitle: String,
        buttonIcon: String? = nil,
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
                Icon(named: icon ?? "crypto-outline", color: Theme.colors.primaryAccent4, size: 24)
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

                PrimaryButton(
                    title: buttonTitle,
                    leadingIcon: buttonIcon,
                    size: .mini,
                    action: action
                )
                    .fixedSize()
                    .showIf(showsActionButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
        }
        .clipShape(
            .rect(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
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
