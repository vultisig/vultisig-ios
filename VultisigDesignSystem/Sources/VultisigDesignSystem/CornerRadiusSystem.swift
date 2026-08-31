import SwiftUI

struct CornerRadiusSystem: CornerRadiusSystemProtocol {
    /// Pin the geometry explicitly so an SDK default cannot restyle surfaces.
    private static let cornerStyle: RoundedCornerStyle = .continuous
    /// SwiftUI clamps this above half the surface height to produce a capsule.
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
