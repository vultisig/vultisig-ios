//
//  ToolbarButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

enum ToolbarButtonType {
    case secondary
    case primary
    case destructive
}

struct ToolbarButton: View {
    let image: String
    let type: ToolbarButtonType
    let action: () -> Void
    
    init(image: String, type: ToolbarButtonType = .primary, action: @escaping () -> Void) {
        self.image = image
        self.type = type
        self.action = action
    }
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button("", systemImage: image, action: action)
                .labelStyle(.toolbar)
        } else {
            CustomToolbarButton(icon: Image(systemName: image), type: type, action: action)
        }
    }
}

private struct CustomToolbarButton: View {
    let icon: Image
    let type: ToolbarButtonType
    let action: () -> Void
    
    init(icon: Image, type: ToolbarButtonType = .primary, action: @escaping () -> Void) {
        self.icon = icon
        self.type = type
        self.action = action
    }
    
    var color: Color {
        switch type {
        case .secondary:
            Color(hex: "787880").opacity(0.32)
        case .primary:
            Theme.colors.primaryAccent3
        case .destructive:
            Theme.colors.alertError
        }
    }
    
    var iconColor: Color {
        switch type {
        case .secondary:
            Theme.colors.textLight
        case .primary, .destructive:
            Theme.colors.textPrimary
        }
    }
    
    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(iconColor)
                .font(.system(size: 17).weight(.medium))
                .padding(12)
                .background(Circle().fill(color))
        }
    }
}
