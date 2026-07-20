//
//  DefiButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiButton: View {
    let title: String
    let icon: ImageResource?
    let type: ButtonType
    let action: () -> Void

    @Environment(\.isEnabled) var isEnabled

    let iconSize: CGFloat = 12
    let iconPadding: CGFloat = 4
    init(title: String, icon: ImageResource? = nil, type: ButtonType = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.type = type
        self.action = action
    }

    var body: some View {
        Button {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            PrimaryButtonView(title: title, paddingLeading: icon != nil ? (iconSize * 2 + iconPadding) / 2 : 0)
        }
        .buttonStyle(PrimaryButtonStyle(type: type, size: .small))
        .overlay(iconView, alignment: .leading)
    }

    @ViewBuilder
    var iconView: some View {
        if let icon {
            Icon(icon, color: Theme.colors.textPrimary, size: iconSize)
                .padding(iconSize)
                .background(Circle().fill(.white.opacity(0.12)))
                .padding(.leading, iconPadding)
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

#Preview {
    VStack {
        DefiButton(title: "Request to bond", icon: .arrowsRotateCenter, action: {})
        DefiButton(title: "Request to bond", icon: .arrowsRotateCenter, action: {})
            .disabled(true)
        DefiButton(title: "Request to bond", icon: .arrowsRotateCenter, type: .secondary, action: {})
        DefiButton(title: "Request to bond", icon: .arrowsRotateCenter, type: .secondary, action: {})
            .disabled(true)
    }
    .padding(.horizontal)
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
