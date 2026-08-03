//
//  ContainerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

import SwiftUI

struct ContainerView<Content: View>: View {
    let content: () -> Content
    /// Defaults to the container step, which is what all but two call sites
    /// are. The exceptions are form controls — a selector sitting in a stack
    /// of text fields — where the radius has to match the fields beside it
    /// rather than the cards elsewhere in the app.
    let radius: CornerRadius

    init(
        radius: CornerRadius = Theme.radius.xl,
        @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.content = content
    }

    var body: some View {
        content()
            .font(Theme.fonts.bodyMMedium)
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .containerStyle(radius: radius)
    }
}
