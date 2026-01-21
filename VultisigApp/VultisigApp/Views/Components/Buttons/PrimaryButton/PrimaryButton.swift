//
//  PrimaryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let leadingIcon: String?
    let trailingIcon: String?
    let isLoading: Bool
    let type: ButtonType
    let size: ButtonSize
    let action: () -> Void
    let reserveTrailingIconSpace: Bool

    let supportsLongPress: Bool
    @Binding var longPressProgress: CGFloat

    init(
        title: String,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.isLoading = isLoading
        self.type = type
        self.size = size
        self.reserveTrailingIconSpace = reserveTrailingIconSpace
        self.supportsLongPress = supportsLongPress
        self._longPressProgress = longPressProgress
        self.action = action
    }

    var body: some View {
        Button {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            PrimaryButtonView(
                title: title,
                leadingIcon: leadingIcon,
                trailingIcon: trailingIcon,
                isLoading: isLoading,
                reserveTrailingIconSpace: reserveTrailingIconSpace
            )
        }
        .buttonStyle(
            PrimaryButtonStyle(
                type: type,
                size: size,
                supportsLongPress: supportsLongPress,
                progress: $longPressProgress
            )
        )
    }
}

#Preview {
    VStack {
        PrimaryButton(title: "Continue", type: .primary, size: .medium) {}
        PrimaryButton(title: "Continue", type: .primary, size: .small) {}
        PrimaryButton(title: "Continue", type: .primary, size: .mini) {}

        PrimaryButton(title: "Continue", type: .secondary, size: .medium) {}
        PrimaryButton(title: "Continue", type: .secondary, size: .small) {}
        PrimaryButton(title: "Continue", type: .secondary, size: .mini) {}
    }
}
