//
//  TapPointerIndicator.swift
//  VultisigApp
//

import SwiftUI

/// A "tap here" pointer: a solid core with a halo that repeatedly expands and
/// fades out, used to call out a target in a tutorial illustration.
///
/// Drawn in SwiftUI rather than Rive: a Rive view hosted inside a macOS sheet
/// loads and advances but never becomes visible, so an equivalent Rive
/// animation renders on iOS and silently disappears on macOS.
struct TapPointerIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPulsing = false

    private let coreDiameter: CGFloat = 10
    private let haloDiameter: CGFloat = 34
    private let pulseDuration: TimeInterval = 1.6

    /// Halo scale relative to `haloDiameter`. Reduce Motion holds it partway
    /// out so the ring stays visibly larger than the core instead of collapsing
    /// behind it; otherwise it expands from the core to full size as it pulses.
    private var haloScale: CGFloat {
        if reduceMotion { return 0.75 }
        return isPulsing ? 1 : coreDiameter / haloDiameter
    }

    /// Halo opacity. Reduce Motion holds a steady faint ring; otherwise it fades
    /// out as the pulse expands.
    private var haloOpacity: Double {
        if reduceMotion { return 0.35 }
        return isPulsing ? 0 : 0.8
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.textPrimary)
                .frame(width: haloDiameter, height: haloDiameter)
                .scaleEffect(haloScale)
                .opacity(haloOpacity)

            Circle()
                .fill(Theme.colors.textPrimary)
                .frame(width: coreDiameter, height: coreDiameter)
        }
        .accessibilityHidden(true)
        .onAppear {
            // Reduce Motion shows a static ring (see haloScale/haloOpacity)
            // rather than pulsing.
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: pulseDuration).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        TapPointerIndicator()
            .frame(width: 40, height: 40)
    }
}
