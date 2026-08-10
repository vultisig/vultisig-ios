//
//  ShimmerViewModifier.swift
//  VultisigApp
//

import SwiftUI

/// A travelling highlight for placeholder content.
///
/// Pairs with `.redacted(reason: .placeholder)`, which supplies the grey bars —
/// this supplies the motion that tells the user the screen is working rather
/// than stuck on an empty state. Masked to the content it decorates, so it
/// lights the placeholder shapes and not the gaps between them.
///
/// The sweep is measured against the content's own width rather than a fixed
/// offset, so it crosses a full-width card and a 40pt chip at the same apparent
/// speed instead of stalling on one and overshooting the other.
struct ShimmerViewModifier: ViewModifier {
    /// Fraction of the content width, from fully off the leading edge to fully
    /// off the trailing edge.
    @State private var phase: CGFloat = -1

    /// A slow repeating sweep is exactly what this setting exists to stop, and
    /// the redacted bars still read as "no value yet" standing still.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                Theme.colors.textPrimary.opacity(0.25),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width)
                        .offset(x: phase * proxy.size.width)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

extension View {
    /// Animates a highlight across placeholder content. Apply to a skeleton,
    /// alongside `.redacted(reason: .placeholder)`.
    func shimmer() -> some View {
        modifier(ShimmerViewModifier())
    }
}
