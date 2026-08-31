import SwiftUI

/// One step of the shared corner-radius scale.
///
/// A token carries both the radius and style so changing the shared geometry
/// does not require edits at each surface.
public struct CornerRadius: Equatable, Sendable {
    /// Radius in points for APIs that cannot accept `shape` directly.
    public let points: CGFloat
    /// How the corner is drawn.
    public let style: RoundedCornerStyle

    /// The rounded rectangle described by this token.
    public var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: points, style: style)
    }

    init(points: CGFloat, style: RoundedCornerStyle) {
        self.points = points
        self.style = style
    }
}
