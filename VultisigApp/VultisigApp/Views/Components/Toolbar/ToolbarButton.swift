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
            Color.white.opacity(0.05)
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
            Button(action: action) {
                iconView
            }
            .buttonStyle(.glassProminent)
            .tint(tintColor)
        } else {
            customButton
        }
#endif
    }
    
    var iconView: some View {
        Icon(named: image, color: Theme.colors.textPrimary, size: 20)
    }
    
    var customButton: some View {
        Button(action: action) {
            iconView
                .padding(12)
                .background(
                    Circle()
                        .fill(.white.opacity(isHovered ? 0.2 : 0.05))
                        .overlay(
                            EllipticalGradient(
                                stops: [
                                    Gradient.Stop(color: Color(red: 0.16, green: 0.59, blue: 0.95), location: 0.00),
                                    Gradient.Stop(color: Color(red: 0.24, green: 0.11, blue: 0.98).opacity(0), location: 1.00),
                                ],
                                center: UnitPoint(x: 0.5, y: 0.5)
                            )
                            .offset(y: 25)
                            .opacity(0.2)
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
