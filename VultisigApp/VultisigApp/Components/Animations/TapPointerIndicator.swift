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

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.textPrimary)
                .frame(width: haloDiameter, height: haloDiameter)
                .scaleEffect(isPulsing ? 1 : coreDiameter / haloDiameter)
                .opacity(isPulsing ? 0 : 0.8)

            Circle()
                .fill(Theme.colors.textPrimary)
                .frame(width: coreDiameter, height: coreDiameter)
        }
        .accessibilityHidden(true)
        .onAppear {
            // Reduce Motion keeps the halo as a static ring rather than pulsing.
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
