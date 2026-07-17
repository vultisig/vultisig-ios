//
//  IconButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct IconButton: View {
    let icon: ImageResource
    let isLoading: Bool
    let type: ButtonType
    let size: ButtonSize
    let action: () -> Void

    init(
        icon: ImageResource,
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
        IconButton(icon: .chevronRight, type: .primary, size: .medium) {}
        IconButton(icon: .chevronRight, type: .primary, size: .small) {}
        IconButton(icon: .chevronRight, type: .primary, size: .mini) {}

        IconButton(icon: .chevronRight, type: .secondary, size: .medium) {}
        IconButton(icon: .chevronRight, type: .secondary, size: .small) {}
        IconButton(icon: .chevronRight, type: .secondary, size: .mini) {}
    }
}
