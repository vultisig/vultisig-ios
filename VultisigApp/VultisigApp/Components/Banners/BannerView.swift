//
//  BannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

struct BannerView<Content: View>: View {
    let bgImage: String
    /// Defaults to the container step. **Every banner in the app takes it**,
    /// including the collected-rewards banner nested inside the referral
    /// section — that is a design decision, not an oversight: banners read as
    /// banners at one radius, and this view's own 24pt padding keeps the two
    /// edges apart where one sits inside another.
    ///
    /// The parameter stays as the seam for a future banner that genuinely has
    /// to step down. There is no such call site today.
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
