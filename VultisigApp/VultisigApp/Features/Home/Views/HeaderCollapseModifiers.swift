//
//  HeaderCollapseModifiers.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/08/2025.
//

import SwiftUI

/// Fades the large balance out as the vault-home top bar collapses over it.
///
/// Deliberately its own `ViewModifier`, and the only thing inside the scroll
/// content that reads `HomeHeaderCollapse`: when the progress moves, SwiftUI
/// re-evaluates this one node and re-applies an opacity to an already-built
/// subtree. Reading the progress directly in the screen's body instead would
/// rebuild the entire content tree on every frame of the transition — the exact
/// cost the scroll-performance work on this screen went to some trouble to
/// remove.
struct HeaderCollapseFade: ViewModifier {
    @ObservedObject var collapse: HomeHeaderCollapse
    let tab: HomeTab

    func body(content: Content) -> some View {
        content.headerCollapseOpacity(collapse.progress(for: tab).expandedOpacity)
    }
}

/// The mirror of `HeaderCollapseFade`, for chrome that belongs to the collapsed
/// state — today the top bar's opaque background. Same observation isolation,
/// same reason: the bar itself must not re-evaluate per frame.
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

    /// Fades the receiver out over the first half of `tab`'s header collapse,
    /// leaving the second half to the top bar's own balance. See
    /// `HeaderCollapseFade`.
    func headerCollapseFade(_ collapse: HomeHeaderCollapse, tab: HomeTab) -> some View {
        modifier(HeaderCollapseFade(collapse: collapse, tab: tab))
    }

    /// Fades the receiver in over the second half of `tab`'s header collapse.
    /// See `HeaderCollapseReveal`.
    func headerCollapseReveal(_ collapse: HomeHeaderCollapse, tab: HomeTab) -> some View {
        modifier(HeaderCollapseReveal(collapse: collapse, tab: tab))
    }
}
