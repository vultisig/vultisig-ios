//
//  DefiButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiButton: View {
    let title: String
    let icon: String
    let type: ButtonType
    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled
    
    let iconSize: CGFloat = 12
    let iconPadding: CGFloat = 4
    init(title: String, icon: String, type: ButtonType = .primary, action: @escaping () -> Void) {
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
            PrimaryButtonView(title: title, paddingLeading: (iconSize * 2 + iconPadding) / 2)
        }
        .buttonStyle(PrimaryButtonStyle(type: type,size: .small))
        .overlay(iconView, alignment: .leading)
    }
    
    var iconView: some View {
        Icon(named: icon, color: Theme.colors.textPrimary, size: iconSize)
            .padding(iconSize)
            .background(Circle().fill(.white.opacity(0.12)))
            .padding(.leading, iconPadding)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

#Preview {
    VStack {
        DefiButton(title: "Request to bond", icon: "arrow-left-right", action: {})
        DefiButton(title: "Request to bond", icon: "arrow-left-right", action: {})
            .disabled(true)
        DefiButton(title: "Request to bond", icon: "arrow-left-right", type: .secondary, action: {})
        DefiButton(title: "Request to bond", icon: "arrow-left-right", type: .secondary, action: {})
            .disabled(true)
    }
    .padding(.horizontal)
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
