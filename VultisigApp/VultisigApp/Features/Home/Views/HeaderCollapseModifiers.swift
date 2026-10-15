//
//  HeaderCollapseModifiers.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/08/2025.
//

import SwiftUI

/// Fades in collapsed-state chrome; its own modifier so only this node re-evaluates per frame.
///
/// It is removed rather than left at zero opacity while the home is expanded,
/// so a transparent full-width background can't swallow taps meant for the
/// content scrolling underneath. `headerCollapseOpacity` covers the one point
/// that removal doesn't: the swap itself, where the background is present but
/// still at zero.
struct HeaderCollapseReveal: ViewModifier {
    @ObservedObject var collapse: HomeHeaderCollapse
    let tab: HomeTab

    func body(content: Content) -> some View {
        let progress = collapse.progress(for: tab)
        content
            .headerCollapseOpacity(progress.collapsedOpacity)
            .showIf(progress.isCollapsed)
    }
}

extension View {
    /// Applies one end of the collapse crossfade, and makes the view inert for
    /// as long as that ramp holds it at zero.
    ///
    /// Fading something out does not remove it: it stays laid out, keeps taking
    /// taps and is still read out by VoiceOver. Everything the crossfade ramps
    /// goes through here, so that neither side of the swap can leave a control
    /// live while it is invisible — without it the top bar's buttons stay fully
    /// tappable through the last sliver of their fade, and its balance is
    /// exposed from the instant it appears at zero opacity.
    func headerCollapseOpacity(_ opacity: Double) -> some View {
        self
            .opacity(opacity)
            .allowsHitTesting(opacity > 0)
            .accessibilityHidden(opacity == 0)
    }

    /// Fades the receiver in over the second half of `tab`'s header collapse.
    /// See `HeaderCollapseReveal`.
    func headerCollapseReveal(_ collapse: HomeHeaderCollapse, tab: HomeTab) -> some View {
        modifier(HeaderCollapseReveal(collapse: collapse, tab: tab))
    }
}
