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
    let showsActionButton: Bool
    let action: () -> Void
    
    init(
        icon: String? = nil,
        title: String,
        subtitle: String,
        buttonTitle: String,
        showsActionButton: Bool = true,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.showsActionButton = showsActionButton
        self.action = action
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 12) {
                Icon(named: icon ?? "crypto-outline", color: Theme.colors.primaryAccent4, size: 24)
                VStack(spacing: 8) {
                    Text(title)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.subtitle)
                    Text(subtitle)
                        .foregroundStyle(Theme.colors.textExtraLight)
                        .font(Theme.fonts.footnote)
                }
                .frame(maxWidth: 263)
                .multilineTextAlignment(.center)
                
                PrimaryButton(title: buttonTitle, size: .mini, action: action)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSecondary))
            GradientListSeparator()
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
