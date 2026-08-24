//
//  CarouselBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation
import SwiftUI

struct CarouselBannerArtworkLayout: Equatable {
    let frameSize: CGFloat
    let scale: CGFloat
    let offset: CGSize
    let trailingInset: CGFloat

    init(
        frameSize: CGFloat = 125,
        scale: CGFloat = 1,
        offset: CGSize = .zero,
        trailingInset: CGFloat = 1
    ) {
        self.frameSize = frameSize
        self.scale = scale
        self.offset = offset
        self.trailingInset = trailingInset
    }
}

protocol CarouselBannerType: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String { get }
    /// Glyph shown in the leading icon tile.
    var icon: ImageResource { get }
    /// Tint applied to `icon`.
    var iconColor: Color? { get }
    /// Decorative artwork anchored to the banner's trailing edge.
    var artwork: ImageResource { get }
    /// Figma crop and transform for the source artwork.
    var artworkLayout: CarouselBannerArtworkLayout { get }
    /// Trailing color in the banner's surface gradient.
    var gradientEndColor: Color { get }
}
