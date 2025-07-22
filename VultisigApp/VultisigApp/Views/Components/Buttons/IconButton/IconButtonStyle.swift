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
            return EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        case .mini:
            return EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        }
    }
    
    func font(for size: ButtonSize) -> Font {
        switch size {
        case .medium, .small: return .body16BrockmannSemiBold
        case .mini: return .body16BrockmannMedium
        }
    }
    
    func cornerRadius(for size: ButtonSize) -> CGFloat {
        switch size {
        case .medium, .small: return 99
        case .mini: return 30
        }
    }
    
    func backgroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        switch type {
        case .primary:
            if !isEnabled {
                return .disabledButtonBackground
            } else if isPressed {
                return .turquoise800
            } else {
                return .turquoise600
            }
            
        case .secondary:
            if !isEnabled {
                return .disabledButtonBackground
            } else if isPressed {
                return .blue500
            } else {
                return .disabledButtonBackground
            }
        }
    }
    
    func foregroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        switch type {
        case .primary:
            if !isEnabled {
                return .disabledText
            } else {
                return .blue800
            }
        case .secondary:
            if !isEnabled {
                return .disabledText
            } else {
                return .neutral50
            }
        }
    }
    
    func borderColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        switch type {
        case .primary:
            return .clear
        case .secondary:
            if !isEnabled {
                return .persianBlue400.opacity(0.6)
            } else {
                return .persianBlue400
            }
        }
    }
    
    func borderWidth(for type: ButtonType) -> CGFloat {
        switch type {
        case .primary: return 0
        case .secondary: return 1
        }
    }
}
