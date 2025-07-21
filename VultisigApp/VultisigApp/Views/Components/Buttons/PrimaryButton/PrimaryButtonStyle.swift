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
    @Environment(\.isEnabled) var isEnabled
    
    init(type: ButtonType = .primary, size: ButtonSize = .medium) {
        self.type = type
        self.size = size
    }
    
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
    }
}

private extension PrimaryButtonStyle {
    func padding(for size: ButtonSize) -> EdgeInsets {
        switch size {
        case .medium:
            return EdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
        case .small:
            return EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        case .mini:
            return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
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
    
    // MARK: - Type Configuration with State-Based Colors
    func backgroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        switch type {
        case .primary:
            if !isEnabled {
                return .disabledButtonBackground
            } else if isPressed {
                return .blue100
            } else {
                return .persianBlue400
            }
            
        case .secondary:
            if !isEnabled {
                return .clear
            } else if isPressed {
                return .blue500
            } else {
                return .clear
            }
        }
    }
    
    func foregroundColor(for type: ButtonType, isPressed: Bool, isEnabled: Bool) -> Color {
        if !isEnabled {
            return .disabledText
        } else {
            return .neutral50
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
