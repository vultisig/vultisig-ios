//
//  BannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI
import VultisigUIResources

struct BannerView<Content: View>: View {
    let bgImage: String
    /// Defaults to the container step. Pass a smaller step when the banner sits
    /// inside another surface, as the collected-rewards banner does.
    let radius: CornerRadius
    let padding: CGFloat
    let content: () -> Content

    init(
        bgImage: String,
        radius: CornerRadius = Theme.radius.xl,
        padding: CGFloat = 24,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content
        self.bgImage = bgImage
        self.radius = radius
        self.padding = padding
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(image)
            .containerStyle(radius: radius)
            .padding(-1) // Cancels containerStyle's outer gutter so the edges meet the neighbours'.
    }

    var image: some View {
        VultisigImage(bgImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
