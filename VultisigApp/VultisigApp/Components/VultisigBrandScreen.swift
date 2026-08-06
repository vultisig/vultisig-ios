//
//  VultisigBrandScreen.swift
//  VultisigApp
//

import SwiftUI

/// The app showing itself rather than its contents: the logo and wordmark,
/// centred on the gradient, edge to edge.
///
/// It exists because three places need to be **indistinguishable** from one
/// another, not merely similar. The privacy cover goes up as the app leaves, the
/// lock screen shows this while it tries the biometric shortcut, and the splash
/// shows it at launch — and a user backgrounding and returning walks through two
/// of them in a row. Any difference between them reads as a flicker: they had
/// drifted to a 64pt logo with no wordmark in one place and a 100pt logo with
/// one in another, and the lock screen's copy sat inside `Screen`, whose safe-area
/// insets moved it up the display relative to the cover's.
///
/// So it is deliberately **not** built on `Screen`. `Screen` is for content, and
/// its insets are exactly what made these two disagree. This is full-bleed by
/// definition, and belongs at the top level of whatever shows it rather than
/// nested inside another container.
struct VultisigBrandScreen: View {

    /// Whether the mark animates.
    ///
    /// Static everywhere it is used to *cover* something, because
    /// `VultisigLogoAnimation` builds its Rive model in `onLoad` — after the
    /// first render — so a cover raised as the app leaves would paint bare
    /// gradient and then pop. The splash is the one place with a user waiting on
    /// it, and the only one that animates.
    var isStatic: Bool = true

    var body: some View {
        ZStack {
            VultisigLogoAnimation(isStatic: isStatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PrimaryBackgroundWithGradient())
        // Full-bleed here rather than at each call site, because "each call
        // site" is how the last gap got in: the cover was written
        // `CoverView().ignoresSafeArea()` and the lock screen's copy was not, so
        // one centred the mark on the display and the other on the safe area —
        // about twelve points apart, and visible as a hop the moment one
        // replaced the other. Owning it means the two cannot disagree again.
        .ignoresSafeArea()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

#Preview {
    VultisigBrandScreen()
}
