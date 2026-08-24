//
//  CarouselBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation
import SwiftUI

struct CarouselBannerArtworkLayout: Equatable {
    private static let figmaBannerWidth: CGFloat = 361

    let frameOrigin: CGPoint
    let frameSize: CGFloat
    let scale: CGFloat
    let offset: CGSize

    init(
        frameOrigin: CGPoint = CGPoint(x: 235, y: -9),
        frameSize: CGFloat = 125,
        scale: CGFloat = 1,
        offset: CGSize = .zero
    ) {
        self.frameOrigin = frameOrigin
        self.frameSize = frameSize
        self.scale = scale
        self.offset = offset
    }

    func frameOrigin(in bannerWidth: CGFloat) -> CGPoint {
        CGPoint(
            x: frameOrigin.x + bannerWidth - Self.figmaBannerWidth,
            y: frameOrigin.y
        )
    }
}

protocol CarouselBannerType: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String { get }
    /// Exact Figma artwork shown in the leading icon tile.
    var icon: ImageResource { get }
    var iconSize: CGFloat { get }
    /// Decorative artwork anchored to the banner's trailing edge.
    var artwork: ImageResource { get }
    /// Figma crop and transform for the source artwork.
    var artworkLayout: CarouselBannerArtworkLayout { get }
    /// Trailing color in the banner's surface gradient.
    var gradientEndColor: Color { get }
}
