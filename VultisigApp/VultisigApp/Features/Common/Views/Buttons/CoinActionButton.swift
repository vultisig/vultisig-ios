//
//  CoinActionButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct CoinActionButton: View {
    @Environment(\.isEnabled) var isEnabled

    let title: String
    let icon: String
    let isHighlighted: Bool
    var action: () -> Void

    var bgColor: Color {
        return isHighlighted ? Theme.colors.bgButtonTertiary : Theme.colors.bgSurface2
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Icon(
                    named: icon,
                    color: Theme.colors.textPrimary,
                    size: 20
                )
                .padding(16)
                .background(bgColor)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .inset(by: 0.5)
                        .stroke(.white.opacity(0.03), lineWidth: 1)
                )

                Text(title)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.caption12)
                    .fixedSize()
            }
            .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CoinActionButton(title: "Swap", icon: "swap", isHighlighted: true) {}
    CoinActionButton(title: "Swap", icon: "swap", isHighlighted: false) {}
    CoinActionButton(title: "Swap", icon: "swap", isHighlighted: true) {}.disabled(true)
    CoinActionButton(title: "Swap", icon: "swap", isHighlighted: false) {}.disabled(true)
}
