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
    var buttonTitle: String { get }
    var image: ImageResource { get }
    var background: String? { get }
    /// When non-nil, the banner renders the compact icon-tile layout with this
    /// glyph in the leading tile (no CTA button, flat surface + border). When
    /// nil, the banner uses the legacy illustration + button layout.
    var tileIcon: ImageResource? { get }
}

extension CarouselBannerType {
    var tileIcon: ImageResource? { nil }
}
