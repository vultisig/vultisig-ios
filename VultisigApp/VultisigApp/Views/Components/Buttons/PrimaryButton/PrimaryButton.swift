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
    
    init(
        title: String,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
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
            PrimaryButtonView(
                title: title,
                leadingIcon: leadingIcon,
                trailingIcon: trailingIcon,
                isLoading: isLoading
            )
        }
        .buttonStyle(PrimaryButtonStyle(type: type, size: size))
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
