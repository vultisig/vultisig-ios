//
//  ToolbarButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

enum ToolbarButtonType {
    case outline
    case confirmation
    case destructive
}

struct ToolbarButton: View {
    @Environment(\.isNativeToolbarItem) private var isNativeToolbarItem
    
    let image: String
    let type: ToolbarButtonType
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    init(image: String, type: ToolbarButtonType = .outline, action: @escaping () -> Void) {
        self.image = image
        self.type = type
        self.action = action
    }
    
    var tintColor: Color {
        switch type {
        case .outline:
            isNativeToolbarItem ? Color.white.opacity(0.05) : Theme.colors.bgSecondary
        case .confirmation:
            Theme.colors.primaryAccent3
        case .destructive:
            Theme.colors.alertError
        }
    }
    
    var body: some View {
#if os(macOS)
        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    iconView
                        .padding(12)
                        .overlay(isHovered ? Circle().fill(.white.opacity(0.1)) : nil)
                }
                .glassEffect(.regular.tint(tintColor).interactive(), in: Circle())
                .clipShape(Circle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
                .buttonStyle(.plain)
            } else {
                customButton
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHovered = hovering
                        }
                    }
            }
        }
#else
        if #available(iOS 26.0, *) {
            // If it's native iOS toolbar, we use the default button with tint as it looks better, toolbar already styles it
            if isNativeToolbarItem {
                Button(action: action) {
                    iconView
                }
                .buttonStyle(.glassProminent)
                .tint(tintColor)
            } else {
                // Otherwise, we customize the glass effect ourselves
                Button(action: action) {
                    iconView
                        .padding(12)
                        .overlay(Circle().inset(by: 0.5).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                        .background(Circle().fill(tintColor))
                }
                .glassEffect(.clear.interactive())
            }
        } else {
            customButton
        }
#endif
    }
    
    var iconView: some View {
        Icon(named: image, color: Theme.colors.textPrimary, size: 20)
    }
    
    // Custom button with "fake" glass effect for styling
    var customButton: some View {
        Button(action: action) {
            iconView
                .padding(12)
                .background(
                    Circle()
                        .fill(tintColor.opacity(isHovered ? 0.2 : 1))
                        .overlay(
                            type == .outline ?
                            EllipticalGradient(
                                stops: [
                                    Gradient.Stop(color: Color(red: 0.16, green: 0.59, blue: 0.95), location: 0.00),
                                    Gradient.Stop(color: Color(red: 0.24, green: 0.11, blue: 0.98).opacity(0), location: 1.00),
                                ],
                                center: UnitPoint(x: 0.5, y: 0.5)
                            )
                            .offset(y: 25)
                            .opacity(0.2)
                            : nil
                        )
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                )
                .overlay(
                    Circle()
                        .inset(by: 0.5)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .clipShape(Circle())
    }
}
