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

struct ToolbarButton<IconContent: View>: View {
    @Environment(\.isNativeToolbarItem) private var isNativeToolbarItem
    
    let image: String
    let iconSize: CGFloat
    let type: ToolbarButtonType
    let action: () -> Void
    let iconContent: (Icon) -> IconContent
    
    @State private var isHovered: Bool = false
    
    init(image: String, iconSize: CGFloat = 20, type: ToolbarButtonType = .outline, action: @escaping () -> Void) where IconContent == Icon {
        self.image = image
        self.type = type
        self.action = action
        self.iconSize = iconSize
        self.iconContent = { icon in icon }
    }
    
    init(image: String, iconSize: CGFloat = 20, type: ToolbarButtonType = .outline, action: @escaping () -> Void, @ViewBuilder iconContent: @escaping (Icon) -> IconContent) {
        self.image = image
        self.type = type
        self.action = action
        self.iconSize = iconSize
        self.iconContent = iconContent
    }
    
    var tintColor: Color {
        switch type {
        case .outline:
            isNativeToolbarItem ? Color.white.opacity(0.05) : Theme.colors.bgSurface1
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
                    transformedIconView
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
                    transformedIconView
                }
                .buttonStyle(.glassProminent)
                .tint(tintColor)
            } else {
                // Otherwise, we customize the glass effect ourselves
                Button(action: action) {
                    transformedIconView
                        .padding(12)
                        .overlay(Circle()
                            .stroke(LinearGradient(colors: [.white, .clear, .clear, .white], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                        .background(Circle().fill(tintColor))
                }
                .glassEffect(.clear.interactive())
            }
        } else {
            customButton
        }
#endif
    }
    
    var transformedIconView: some View {
        iconContent(iconView)
    }
    
    var iconView: Icon {
        Icon(named: image, color: Theme.colors.textPrimary, size: iconSize)
    }
    
    // Custom button with "fake" glass effect for styling
    var customButton: some View {
        Button(action: action) {
            transformedIconView
                .padding(12)
                .background(
                    Circle()
                        .fill(tintColor.opacity(isHovered ? 0.2 : 1))
                        .stroke(LinearGradient(colors: [.white, .clear, .clear, .white], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 20
                            )
                            .blendMode(.screen)
                        )
                        .opacity(0.1)
                        .offset(.init(width: 10, height: 10))
                        .blur(radius: 5)
                )
  
        }
        .buttonStyle(.plain)
        .clipShape(Circle())
    }
}
