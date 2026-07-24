//
//  NotchedRectangle.swift
//  VultisigApp
//

import SwiftUI

/// Rounded rectangle with a concave semicircle removed from the bottom edge,
/// centered horizontally — the seat for the swap-direction toggle button that
/// sits over the gap between the stacked Sell/Buy cards.
///
/// Because it is a real `Shape`, both the fill and the border follow the cutout,
/// so the notch works over any background (gradient, image) instead of only over
/// a solid page color that page-colored "filler" paint could hide behind.
///
/// Rotate 180° (as `SwapFromToField` already does for the "to"/Buy card) to
/// mirror it: the 24/12 corners swap and the notch moves to the top edge.
struct NotchedRectangle: Shape {
    var topLeadingRadius: CGFloat = 24
    var topTrailingRadius: CGFloat = 24
    var bottomLeadingRadius: CGFloat = 12
    var bottomTrailingRadius: CGFloat = 12
    /// Radius of the semicircular cavity. ≈ the toggle button's outer radius plus
    /// a hairline gap so the button's stroke ring reads as seated in the notch.
    var notchRadius: CGFloat = 21

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Clamp so unusual/compact frames can't reverse segments or push the
        // corners and notch past each other: corners fit within half the smaller
        // side, and the notch stays on the bottom edge between the bottom corners
        // (and no deeper than the card).
        let maxCorner = max(0, min(rect.width, rect.height) / 2)
        let tl = clamp(topLeadingRadius, upperBound: maxCorner)
        let tr = clamp(topTrailingRadius, upperBound: maxCorner)
        let bl = clamp(bottomLeadingRadius, upperBound: maxCorner)
        let br = clamp(bottomTrailingRadius, upperBound: maxCorner)
        let bottomRoom = min(rect.midX - (rect.minX + bl), (rect.maxX - br) - rect.midX)
        let notch = clamp(notchRadius, upperBound: min(bottomRoom, rect.height))

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr),
            radius: tr
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY),
            radius: br
        )
        path.addLine(to: CGPoint(x: rect.midX + notch, y: rect.maxY))
        // Concave semicircle biting UP into the card. SwiftUI's y-axis points
        // down, so `clockwise: true` sweeps 0°→180° through -90° (up), keeping the
        // arc inside the card; `clockwise: false` would bulge it out the bottom.
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: notch,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl),
            radius: bl
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY),
            radius: tl
        )
        path.closeSubpath()
        return path
    }

    /// Constrains a radius to `0...upperBound`, tolerating a negative
    /// `upperBound` (a frame too small to host the feature) by collapsing to 0.
    private func clamp(_ value: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, 0), max(upperBound, 0))
    }
}

#Preview {
    ZStack {
        Theme.colors.bgPrimary
        VStack(spacing: 12) {
            NotchedRectangle()
                .foregroundStyle(Theme.colors.bgSurface1)
                .overlay(NotchedRectangle().stroke(Theme.colors.bgSurface2, lineWidth: 1))
                .frame(height: 96)
            NotchedRectangle()
                .foregroundStyle(Theme.colors.bgSurface1)
                .overlay(NotchedRectangle().stroke(Theme.colors.bgSurface2, lineWidth: 1))
                .rotationEffect(.degrees(180))
                .frame(height: 96)
        }
        .padding(16)
    }
}
