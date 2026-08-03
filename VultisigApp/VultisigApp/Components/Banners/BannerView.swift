//
//  BannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

struct BannerView<Content: View>: View {
    let bgImage: String
    /// Defaults to the container step, because a banner is usually the outer
    /// surface on its page. A banner rendered *inside* another container has to
    /// pass a smaller step so the nesting still reads — this view is used both
    /// ways on the referral screen.
    let radius: CornerRadius
    let content: () -> Content

    init(
        bgImage: String,
        radius: CornerRadius = Theme.radius.xl,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content
        self.bgImage = bgImage
        self.radius = radius
    }

    var body: some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(image)
            .containerStyle(radius: radius)
    }

    var image: some View {
        Image(bgImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
