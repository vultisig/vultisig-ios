//
//  SettingsCTAButton.swift
//  VultisigApp
//

import SwiftUI

/// The design's buttons on the settings sub-screens: 46 tall, a 14pt label, and
/// their own fills and bevels.
struct SettingsCTAButtonStyle: ButtonStyle {
    enum Width {
        /// Fills the screen width, with a medium label.
        case fill
        /// Hugs a semibold label.
        case hug
    }

    enum Kind {
        case primary, secondary, destructive
    }

    enum Weight {
        case medium, semibold
    }

    private static let height: CGFloat = 46
    private static let hugHorizontalPadding: CGFloat = 32
    private static let primaryFill = Color(hex: "0B4EFF")
    private static let primaryPressedFill = Color(hex: "0A45E0")
    private static let primaryBottomBevel = Color(hex: "0F1C3E").opacity(0.48)
    private static let primaryTopBevel = Color.white.opacity(0.24)
    private static let secondaryBottomBevel = Color(hex: "0F1C3E")
    private static let secondaryTopBevel = Color.white.opacity(0.1)

    let width: Width
    var kind: Kind = .primary
    /// Overrides the label weight the width implies, where the design mixes them.
    var weight: Weight?

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(labelFont)
            .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textButtonDisabled)
            .frame(maxWidth: width == .fill ? .infinity : nil)
            .padding(.horizontal, Self.hugHorizontalPadding)
            .frame(minHeight: Self.height)
            .background(background(isPressed: configuration.isPressed))
            .contentShape(Capsule(style: .circular))
    }

    private var labelFont: Font {
        (weight ?? (width == .fill ? .medium : .semibold)) == .medium
            ? Theme.fonts.buttonSMedium
            : Theme.fonts.buttonSSemibold
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        let capsule = Capsule(style: .circular)
        if !isEnabled {
            capsule
                .fill(kind == .secondary ? .clear : Theme.colors.bgButtonDisabled)
                .strokeBorder(
                    kind == .secondary ? Theme.colors.borderExtraLight : Theme.colors.bgButtonTertiary.opacity(0.6),
                    lineWidth: 1
                )
        } else {
            switch kind {
            case .primary:
                capsule.fill(
                    (isPressed ? Self.primaryPressedFill : Self.primaryFill)
                        .shadow(.inner(color: Self.primaryBottomBevel, radius: 0.8, y: -1))
                        .shadow(.inner(color: Self.primaryTopBevel, radius: 0.95, y: 1))
                )
            case .secondary:
                capsule
                    .fill(
                        (isPressed ? Theme.colors.bgButtonSecondaryPressed : Theme.colors.bgButtonSecondary)
                            .shadow(.inner(color: Self.secondaryBottomBevel, radius: 0.25, y: -1))
                            .shadow(.inner(color: Self.secondaryTopBevel, radius: 0.5, y: 1))
                    )
                    .strokeBorder(Theme.colors.borderExtraLight, lineWidth: 1)
            case .destructive:
                capsule.fill(Theme.colors.alertError.opacity(isPressed ? 0.7 : 1))
            }
        }
    }
}

/// A `SettingsCTAButtonStyle` button with the app's tap feedback.
struct SettingsCTAButton: View {
    let title: String
    let width: SettingsCTAButtonStyle.Width
    var kind: SettingsCTAButtonStyle.Kind = .primary
    var weight: SettingsCTAButtonStyle.Weight?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title.localized)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .buttonStyle(SettingsCTAButtonStyle(width: width, kind: kind, weight: weight))
    }
}
