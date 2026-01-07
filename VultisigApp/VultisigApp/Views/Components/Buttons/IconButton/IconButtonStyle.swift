//
//  IconButtonStyle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct IconButtonStyle: ButtonStyle {
    let type: ButtonType
    let size: ButtonSize
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font(for: size))
            .padding(padding(for: size))
            .background(backgroundColor(for: type, isPressed: configuration.isPressed, isEnabled: isEnabled))
            .foregroundColor(foregroundColor(for: type, isPressed: configuration.isPressed, isEnabled: isEnabled))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius(for: size))
                    .stroke(borderColor(for: type, isPressed: configuration.isPressed, isEnabled: isEnabled),
                           lineWidth: borderWidth(for: type))
            )
            .cornerRadius(cornerRadius(for: size))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius(for: size)))
    }
}

private extension IconButtonStyle {
    func padding(for size: ButtonSize) -> EdgeInsets {
        switch size {
        case .medium:
            return EdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
        case .small:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .mini, .squared:
            return EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        }
    }
    
    func font(for size: ButtonSize) -> Font {
        switch size {
        case .medium, .small, .squared: return Theme.fonts.buttonRegularSemibold
        case .mini: return Theme.fonts.bodyMMedium
        }
    }
    
    func cornerRadius(for size: ButtonSize) -> CGFloat {
        switch size {
        case .medium, .small: return 99
        case .mini, .squared: return 30
        }
    }
    
    func backgroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return Theme.colors.bgButtonDisabled
        }
        
        switch type {
        case .alert:
            if isPressed {
                return Theme.colors.alertError.opacity(0.7)
            } else {
                return Theme.colors.alertError
            }
        case .primary, .primarySuccess:
            if isPressed {
                return Theme.colors.bgButtonPrimaryPressed
            } else {
                return Theme.colors.bgButtonPrimary
            }
        case .secondary:
            if isPressed {
                return Theme.colors.bgButtonSecondaryPressed
            } else {
                return Theme.colors.bgButtonDisabled
            }
        case .outline:
            return .clear
        }
    }
    
    func foregroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        switch type {
        case .primary, .alert, .primarySuccess:
            if !isEnabled {
                return Theme.colors.textButtonDisabled
            } else {
                return Theme.colors.textButtonDark
            }
        case .secondary:
            if !isEnabled {
                return Theme.colors.textButtonDisabled
            } else {
                return Theme.colors.textPrimary
            }
        case .outline:
            if !isEnabled {
                return Theme.colors.textButtonDisabled
            } else {
                return Theme.colors.textPrimary
            }
        }
    }
    
    func borderColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
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
