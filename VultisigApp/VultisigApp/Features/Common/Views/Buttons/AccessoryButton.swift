//
//  AccessoryButton.swift
//  VultisigApp
//

import SwiftUI

struct AccessoryButton: View {
    let icon: ImageResource
    let label: String?
    var action: () -> Void

    init(icon: ImageResource, label: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(icon, color: Theme.colors.textPrimary, size: 16)
                if let label {
                    Text(label)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
            }
            .padding(12)
            .background(Capsule().fill(Theme.colors.bgSurface1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        AccessoryButton(icon: .magnifier) {}
        AccessoryButton(icon: .accessoryPen, label: "Chains") {}
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
