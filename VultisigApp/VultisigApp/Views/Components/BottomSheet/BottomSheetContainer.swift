//
//  BottomSheetContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct BottomSheetContainer<Content: View>: View {
    let showCloseButton: Bool
    let content: Content
    let onDismiss: () -> Void

    init(showCloseButton: Bool, @ViewBuilder content: () -> Content, onDismiss: @escaping () -> Void) {
        self.showCloseButton = showCloseButton
        self.content = content()
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.borderBlue)
                .frame(width: 64, height: 4)
                .cornerRadius(99)
            content
        }
        .background(Color.blue600)
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }
}
