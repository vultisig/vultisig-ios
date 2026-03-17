//
//  PrimaryButtonStyle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    let type: ButtonType
    let size: ButtonSize
    let supportsLongPress: Bool
    @Binding var progress: CGFloat
    @Environment(\.isEnabled) var isEnabled

    init(
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        supportsLongPress: Bool = false,
        progress: Binding<CGFloat> = .constant(0)
    ) {
        self.type = type
        self.size = size
        self.supportsLongPress = supportsLongPress
        self._progress = progress
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font(for: size))
            .padding(padding(for: size))
            .background(
                ZStack(alignment: .leadingLastTextBaseline) {
                    backgroundColor(for: type, isPressed: configuration.isPressed, isEnabled: isEnabled)
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .stroke(borderColor(for: type, isEnabled: isEnabled),
                                lineWidth: borderWidth(for: type))
                        .scaleEffect(CGSize(width: progress, height: 1), anchor: .leading)
                }
            )
            .foregroundColor(foregroundColor(for: type, isEnabled: isEnabled))
            .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius(for: size))
                        .stroke(borderColor(for: type, isEnabled: isEnabled),
                                lineWidth: borderWidth(for: type))
            )
            .cornerRadius(cornerRadius(for: size))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius(for: size)))
    }
}

private extension PrimaryButtonStyle {
    func padding(for size: ButtonSize) -> EdgeInsets {
        switch size {
        case .medium:
            return EdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0)
        case .small:
            return EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        case .mini:
            return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        case .squared:
            return EdgeInsets(top: 20, leading: 12, bottom: 20, trailing: 12)
        }
    }

    func font(for size: ButtonSize) -> Font {
        switch size {
        case .medium, .small: return Theme.fonts.buttonRegularSemibold
        case .mini: return Theme.fonts.caption12
        case .squared: return Theme.fonts.buttonSSemibold
        }
    }

    func cornerRadius(for size: ButtonSize) -> CGFloat {
        switch size {
        case .medium, .small, .mini: 99
        case .squared: 12
        }
    }

    // MARK: - Type Configuration with State-Based Colors
    func backgroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        let shouldHighlight = isPressed && !supportsLongPress
        switch type {
        case .alert:
            if !isEnabled {
                return Theme.colors.bgButtonDisabled
            } else if isPressed {
                return Theme.colors.alertError.opacity(0.7)
            } else {
                return Theme.colors.alertError
            }
        case .primary:
            if !isEnabled {
                return Theme.colors.bgButtonDisabled
            } else if shouldHighlight {
                return Theme.colors.bgButtonTertiaryPressed
            } else {
                return Theme.colors.bgButtonTertiary
            }

        case .secondary:
            if !isEnabled {
                return .clear
            } else if shouldHighlight {
                return Theme.colors.bgButtonSecondaryPressed
            } else {
                return Theme.colors.bgButtonSecondary
            }
        case .primarySuccess:
            if !isEnabled {
                return Theme.colors.bgButtonDisabled
            } else {
                return Theme.colors.bgButtonPrimary.opacity(isPressed ? 0.7 : 1)
            }
        case .outline:
            return .clear
        }
    }

    func foregroundColor(for type: ButtonType, isEnabled: Bool) -> Color {
        if !isEnabled {
            return Theme.colors.textButtonDisabled
        }
        switch type {
        case .primarySuccess:
            return Theme.colors.textButtonDark
        case .outline:
            return Theme.colors.textPrimary
        default:
            return Theme.colors.textPrimary
        }

    }

    func borderColor(for type: ButtonType, isEnabled: Bool) -> Color {
        switch type {
        case .primary, .alert, .primarySuccess:
            return .clear
        case .secondary:
            if !isEnabled {
                return Theme.colors.bgButtonTertiary.opacity(0.6)
            } else {
                return Theme.colors.bgButtonTertiary
            }
        case .outline:
             if !isEnabled {
                 return Theme.colors.bgButtonTertiary.opacity(0.6)
             } else {
                 return Theme.colors.bgButtonTertiary
             }
        }
    }

    func borderWidth(for type: ButtonType) -> CGFloat {
        switch type {
        case .primary, .alert, .primarySuccess: return 0
        case .secondary: return 1
        case .outline: return 1
        }
    }
}
