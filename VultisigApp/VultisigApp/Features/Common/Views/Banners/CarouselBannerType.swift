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
    var iconColor: Color { get }
}
