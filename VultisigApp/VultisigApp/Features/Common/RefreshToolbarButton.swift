//
//  RefreshToolbarButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 14/10/2025.
//

import SwiftUI

struct RefreshToolbarButton: View {
    var onRefresh: () -> Void

    @State private var isRefreshing = false
    @State private var disabled = false

    var body: some View {
        ToolbarButton(image: "refresh", action: onPress) { icon in
            icon
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
        }
        .disabled(disabled)
    }

    func onPress() {
        self.disabled = true
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            isRefreshing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.disabled = false
            withAnimation(.linear(duration: 0.3)) {
                isRefreshing = false
            }
        }
        onRefresh()
    }
}
