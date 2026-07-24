//
//  NotchedRectangle.swift
//  VultisigApp
//

import SwiftUI

/// The vertical gap between the two stacked swap cards (Sell/Buy), shared by the
/// Market and Limit forms as the single source of truth. Used for BOTH the
/// inter-card `VStack(spacing:)` AND the notch-center inset (`swapCardSpacing / 2`):
/// dropping each card's notch center half the gap makes the two cards' notches
/// meet as ONE full circle centered on the toggle, instead of a stadium.
let swapCardSpacing: CGFloat = 12

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
    /// How far below the bottom edge (into the inter-card gap) the notch circle's
    /// center sits. Set to half the gap between the two stacked cards so both
    /// cards' notches become caps of one circle centered on the toggle. `0` keeps
    /// a pure edge-centered semicircle.
    var notchCenterInset: CGFloat = 0

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
        // Drop the notch circle's center below the bottom edge, into the inter-card
        // gap, by `notchCenterInset`. The mirrored (rotated-180°) card does the same,
        // so the two cards' notches become caps of ONE circle centered on the gap —
        // the toggle then seats in a full round hole, not a stadium. `drop == 0`
        // reduces exactly to the original edge-centered semicircle. The circle meets
        // the bottom edge `halfChord` either side of center; `beta` is the tilt of
        // those crossings off horizontal.
        let drop = clamp(notchCenterInset, upperBound: notch)
        let halfChord = (notch * notch - drop * drop).squareRoot()
        let beta = notch > 0 ? asin(Double(drop / notch)) : 0

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
        path.addLine(to: CGPoint(x: rect.midX + halfChord, y: rect.maxY))
        // Concave arc biting UP into the card — the cap of the gap-centered circle.
        // SwiftUI's y-axis points down, so `clockwise: true` sweeps from the right
        // crossing (-beta) up over the top to the left crossing (180°+beta), keeping
        // the arc inside the card (verified via snapshot); `clockwise: false` would
        // bulge it out the bottom. At `drop == 0` this is start 0° / end 180°.
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY + drop),
            radius: notch,
            startAngle: .radians(-beta),
            endAngle: .radians(.pi + beta),
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
        ZStack {
            VStack(spacing: swapCardSpacing) {
                NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
                    .foregroundStyle(Theme.colors.bgSurface1)
                    .overlay(
                        NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
                            .stroke(Theme.colors.bgSurface2, lineWidth: 1)
                    )
                    .frame(height: 96)
                NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
                    .foregroundStyle(Theme.colors.bgSurface1)
                    .overlay(
                        NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
                            .stroke(Theme.colors.bgSurface2, lineWidth: 1)
                    )
                    .rotationEffect(.degrees(180))
                    .frame(height: 96)
            }
            // ~38pt stand-in for SwapAssetsButton, centered in the gap: the two
            // cards' notches should frame it as one clean full circle.
            Circle()
                .fill(Theme.colors.bgButtonTertiary)
                .frame(width: 34, height: 34)
                .padding(2)
                .overlay(Circle().stroke(Theme.colors.bgSurface2))
        }
        .padding(16)
    }
}
