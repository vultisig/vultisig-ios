//
//  Box.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct BoxView<Content: View>: View {
    let padding: CGFloat
    let content: () -> Content
    
    init(padding: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }
    
    var body: some View {
        content()
            .font(Theme.fonts.bodyMMedium)
            .padding(padding)
            .background(Theme.colors.bgButtonDisabled.opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
            .padding(1)
    }
}
