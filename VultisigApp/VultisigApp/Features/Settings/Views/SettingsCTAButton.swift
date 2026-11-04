//
//  SettingsCTAButton.swift
//  VultisigApp
//

import SwiftUI

/// The design's primary button on the settings sub-screens: 46 tall, a 14pt
/// label, and its own blue and bevel.
struct SettingsCTAButtonStyle: ButtonStyle {
    enum Width {
        /// Fills the screen width, with a medium label.
        case fill
        /// Hugs a semibold label.
        case hug
    }

    private static let height: CGFloat = 46
    private static let hugHorizontalPadding: CGFloat = 32
    private static let fill = Color(hex: "0B4EFF")
    private static let pressedFill = Color(hex: "0A45E0")
    private static let bottomBevel = Color(hex: "0F1C3E").opacity(0.48)
    private static let topBevel = Color.white.opacity(0.24)

    let width: Width

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(width == .fill ? Theme.fonts.buttonSMedium : Theme.fonts.buttonSSemibold)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(maxWidth: width == .fill ? .infinity : nil)
            .padding(.horizontal, Self.hugHorizontalPadding)
            .frame(height: Self.height)
            .background(
                Capsule(style: .circular)
                    .fill(
                        (configuration.isPressed ? Self.pressedFill : Self.fill)
                            .shadow(.inner(color: Self.bottomBevel, radius: 0.8, y: -1))
                            .shadow(.inner(color: Self.topBevel, radius: 0.95, y: 1))
                    )
            )
            .contentShape(Capsule(style: .circular))
    }
}

/// A `SettingsCTAButtonStyle` button with the app's tap feedback.
struct SettingsCTAButton: View {
    let title: String
    let width: SettingsCTAButtonStyle.Width
    let action: () -> Void

    var body: some View {
        Button {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            Text(title.localized)
        }
        .buttonStyle(SettingsCTAButtonStyle(width: width))
    }
}
