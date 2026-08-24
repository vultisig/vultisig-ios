//
//  CarouselBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation
import SwiftUI

protocol CarouselBannerType: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String { get }
    /// Glyph shown in the leading icon tile.
    var icon: ImageResource { get }
    /// Tint applied to `icon`.
    var iconColor: Color? { get }
    /// Decorative artwork anchored to the banner's trailing edge.
    var artwork: ImageResource { get }
    /// Figma frame used to crop the square artwork inside the 81pt card.
    var artworkSize: CGFloat { get }
    /// Trailing color in the banner's surface gradient.
    var gradientEndColor: Color { get }
}
