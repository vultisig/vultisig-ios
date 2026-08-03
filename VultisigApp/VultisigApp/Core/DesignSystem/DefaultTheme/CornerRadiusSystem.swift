//
//  CornerRadiusSystem.swift
//  DesignSystem
//

import SwiftUI

struct CornerRadiusSystem: CornerRadiusSystemProtocol {
    /// The one place the app's corner geometry is decided. Every token below is
    /// built with this style, so changing the app's corner shape is this single
    /// line — no call site names a style.
    ///
    /// `.continuous` is the app's current geometry, not a new choice.
    /// `RoundedRectangle(cornerRadius:)`, `Shape.rect(cornerRadius:)` and the
    /// deprecated `View.cornerRadius(_:)` all default their style, and the SDK
    /// the app builds against defaults it to `.continuous`. Every rounded
    /// surface therefore already renders continuous, whether or not it says so.
    ///
    /// Naming it here is the point: that default is Apple's to change, and it
    /// has changed. Sites that spell it out are pinned; sites that leave it
    /// implicit restyle themselves under a new SDK. The token pins it for every
    /// surface that adopts a token.
    private static let cornerStyle: RoundedCornerStyle = .continuous

    /// `pill` has to stay above half of the surface it is applied to: SwiftUI
    /// clamps a corner radius to half the smaller dimension, and that clamp is
    /// what produces a capsule. So the number is not "big enough to look
    /// round", it is a bound — a surface 200,000pt across would out-run it,
    /// which is an order of magnitude beyond a 5K display. Kept private so no
    /// call site ever writes one of the "fully round" magic numbers.
    private static let pillPoints: CGFloat = 100_000

    var xs: CornerRadius { radius(4) }
    var sm: CornerRadius { radius(8) }
    var md: CornerRadius { radius(12) }
    var lg: CornerRadius { radius(16) }
    var xl: CornerRadius { radius(24) }
    var pill: CornerRadius { radius(Self.pillPoints) }

    private func radius(_ points: CGFloat) -> CornerRadius {
        CornerRadius(points: points, style: Self.cornerStyle)
    }
}
