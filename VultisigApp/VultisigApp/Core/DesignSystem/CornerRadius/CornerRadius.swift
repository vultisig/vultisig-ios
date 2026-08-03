//
//  CornerRadius.swift
//  DesignSystem
//

import SwiftUI

/// One step of the app's corner-radius scale.
///
/// A token carries both the radius **and** the corner style, so a call site
/// never names either one: it asks for `Theme.radius.lg` and gets whatever
/// geometry the design system currently defines. That makes a change of corner
/// shape an edit inside `CornerRadiusSystem` rather than a sweep across every
/// rounded surface — and it stops the shape being decided by the SDK, which
/// defaults the style of `RoundedRectangle(cornerRadius:)` and can change what
/// that default is.
///
/// Values live in `CornerRadiusSystem`; this type is only the primitive, the
/// same way `FontStyle` is the primitive behind `FontSystem`.
public struct CornerRadius: Equatable {
    /// Radius in points.
    ///
    /// Use this only where a raw `CGFloat` is unavoidable — for example
    /// `UnevenRoundedRectangle` / `.rect(topLeadingRadius:…)`, which rounds
    /// corners individually and so cannot take a `shape`. Everywhere else,
    /// prefer `shape` or the `cornerRadius(_:)` view modifier so the corner
    /// style travels with the radius.
    ///
    /// Where you do reach for it, pass `style` alongside. A radius taken from a
    /// token and a style left to the SDK is the one combination that quietly
    /// stops tracking the design system.
    public let points: CGFloat

    /// How the corner is drawn. Set once, for the whole scale, by
    /// `CornerRadiusSystem`.
    public let style: RoundedCornerStyle

    /// The rounded rectangle this token describes.
    ///
    /// Deliberately a concrete `RoundedRectangle` rather than `AnyShape`:
    /// `RoundedRectangle` is an `InsettableShape`, which keeps `.strokeBorder`
    /// and `.inset(by:)` available at the call sites that already use them.
    public var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: points, style: style)
    }
}

extension View {
    /// Clips the view to the given radius token.
    ///
    /// Overloads SwiftUI's deprecated `cornerRadius(_:antialiased:)` on the
    /// token type, so a tokenised call site reads the same as the literal one
    /// it replaces while routing through `clipShape` — the replacement Apple's
    /// deprecation points at.
    func cornerRadius(_ radius: CornerRadius) -> some View {
        clipShape(radius.shape)
    }
}
