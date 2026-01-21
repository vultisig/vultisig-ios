//
//  IconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct IconButton: View {
    let icon: String
    let isLoading: Bool
    let type: ButtonType
    let size: ButtonSize
    let action: () -> Void

    init(
        icon: String,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isLoading = isLoading
        self.type = type
        self.size = size
        self.action = action
    }

    var body: some View {
        Button {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            IconButtonView(
                icon: icon,
                isLoading: isLoading
            )
        }
        .buttonStyle(IconButtonStyle(type: type, size: size))
    }
}

#Preview {
    VStack {
        IconButton(icon: "chevron-right", type: .primary, size: .medium) {}
        IconButton(icon: "chevron-right", type: .primary, size: .small) {}
        IconButton(icon: "chevron-right", type: .primary, size: .mini) {}

        IconButton(icon: "chevron-right", type: .secondary, size: .medium) {}
        IconButton(icon: "chevron-right", type: .secondary, size: .small) {}
        IconButton(icon: "chevron-right", type: .secondary, size: .mini) {}
    }
}
