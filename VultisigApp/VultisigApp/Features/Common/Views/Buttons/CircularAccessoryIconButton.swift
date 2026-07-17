//
//  CircularAccessoryIconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct CircularAccessoryIconButton: View {
    enum ButtonType {
        case primary
        case secondary
    }

    let icon: ImageResource
    let type: ButtonType
    var action: () -> Void

    init(icon: ImageResource, type: ButtonType = .primary, action: @escaping () -> Void) {
        self.icon = icon
        self.type = type
        self.action = action
    }

    var iconColor: Color {
        switch type {
        case .primary:
            Theme.colors.textPrimary
        case .secondary:
            Theme.colors.primaryAccent4
        }
    }

    var body: some View {
        Button(action: action) {
            Icon(icon, color: iconColor, size: 16)
                .padding(12)
                .background(Circle().fill(Theme.colors.bgButtonSecondary))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScrollView {
        CircularAccessoryIconButton(icon: .gear) {}
        CircularAccessoryIconButton(icon: .xmark) {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
