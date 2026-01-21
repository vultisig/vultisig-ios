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

    let icon: String
    let type: ButtonType
    var action: () -> Void

    init(icon: String, type: ButtonType = .primary, action: @escaping () -> Void) {
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
            Icon(named: icon, color: iconColor, size: 16)
                .padding(12)
                .background(Circle().fill(Theme.colors.bgButtonSecondary))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScrollView {
        CircularAccessoryIconButton(icon: "settings") {}
        CircularAccessoryIconButton(icon: "x") {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
