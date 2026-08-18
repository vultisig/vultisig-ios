//
//  HeaderCollapseProgress.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/08/2025.
//

import Foundation

/// How far the vault-home top bar has collapsed, as a 0…1 value derived from
/// the scroll offset, plus the two fade ramps that value drives.
///
/// The large balance in the scroll content and the balance in the top bar are
/// faded over **non-overlapping** stretches of the progress, meeting at
/// `midpoint`: everything belonging to the expanded state fades out over
/// `0…midpoint`, everything belonging to the collapsed state fades in over
/// `midpoint…1`. `expandedOpacity` and `collapsedOpacity` are therefore never
/// both greater than zero, so the two balances can never be legible at the same
/// time — and because the whole transition is a function of the scroll offset it
/// scrubs with the drag and reverses with it, instead of running on its own
/// wall-clock timeline.
///
/// The two stretches are not halves in general. They measure different things —
/// the first is the height of the content being faded, the second is the fixed
/// `barFadeDistance` — so `midpoint` sits wherever the tab's content ends. It is
/// one half only where those two coincide, as they do on the wallet tab.
struct HeaderCollapseProgress: Equatable {
    /// Scroll distance over which the top bar's own chrome — its balance and its
    /// opaque background — comes in, once the content's balance has gone.
    ///
    /// Fixed, and deliberately independent of what the tab fades OUT. The
    /// background is what stops the list showing through the bar, so the window
    /// where content is under a still-translucent bar is exactly this long on
    /// every tab. Scaling it with the outgoing content's height instead would
    /// stretch that window in proportion — on the DeFi tab, to the entire height
    /// of the banner.
    static let barFadeDistance: CGFloat = 55

    /// Where the expanded state has finished fading out and the collapsed state
    /// starts fading in, as a fraction of the whole collapse. The top bar swaps
    /// its contents exactly here, which is the one point where both ramps are
    /// zero.
    ///
    /// Derived rather than fixed at one half, because the two sides measure
    /// different things: the expanded side is the height of the content being
    /// faded (per-tab), the collapsed side is `barFadeDistance` (constant). They
    /// coincide at one half only for a tab whose content happens to be
    /// `barFadeDistance` tall — which the wallet's is, so its behaviour is
    /// unchanged to the point.
    let midpoint: Double

    /// Scroll distance, in points, over which the whole collapse plays out. The
    /// first half of it fades the large balance away as it travels towards the
    /// header edge; the second half brings the header balance in.
    static let defaultDistance: CGFloat = 110

    /// The DeFi tab's collapse distance: the banner's height, then the fixed
    /// `barFadeDistance` for the top bar to come in.
    ///
    /// The banner's height, because the expanded ramp is what fades it out and
    /// it must not finish early: `.opacity` does not reclaim layout, so a banner
    /// emptied while it is still on screen reads as a blank gap between the top
    /// bar and the list — most visibly when the user stops mid-scroll.
    ///
    /// Added to rather than scaled, so the bar's entrance stays the same length
    /// as everywhere else. Doubling the whole distance instead would also double
    /// the window in which the list scrolls under a bar that has not finished
    /// becoming opaque — trading the blank gap for a see-through header.
    ///
    /// The wallet tab keeps `defaultDistance`: the balance it fades is text
    /// rather than a fixed-height card, and `barFadeDistance` tall, so its ramps
    /// are unchanged to the point.
    ///
    /// Stated here rather than read off the view — this is the home model and
    /// must not reach into a feature's view layer — so a test pins it to
    /// `DefiMainBalanceView.bannerHeight` instead, and the gate catches a drift
    /// that would otherwise only show up as the original bug.
    static let defiBannerDistance: CGFloat = 135 + barFadeDistance

    /// The collapse distance for `tab`, since what each tab fades is a different
    /// height and the ramp has to match it.
    static func distance(for tab: HomeTab) -> CGFloat {
        switch tab {
        case .defi: defiBannerDistance
        case .wallet, .camera: defaultDistance
        }
    }

    static let expanded = HeaderCollapseProgress(value: 0, midpoint: 0.5)

    /// `0` = fully expanded (large balance in the content), `1` = fully
    /// collapsed (balance in the top bar).
    let value: Double

    private init(value: Double, midpoint: Double) {
        self.value = value
        self.midpoint = midpoint
    }

    /// The fraction of `distance` after which the content has finished fading.
    private static func midpoint(for distance: CGFloat) -> Double {
        guard distance > barFadeDistance else { return 0.5 }
        return Double((distance - barFadeDistance) / distance)
    }

    /// - Parameters:
    ///   - offset: the scroll content's `minY` in the scroll view's coordinate
    ///     space. Equal to `restingOffset` at scroll position zero, decreasing
    ///     as the user scrolls down, larger than it during a rubber-band
    ///     overscroll.
    ///   - restingOffset: that same value at scroll position zero — i.e. the
    ///     scroll view's top inset.
    ///   - distance: how far the user has to scroll for the collapse to
    ///     complete.
    init(offset: CGFloat, restingOffset: CGFloat, distance: CGFloat = Self.defaultDistance) {
        guard distance > 0 else {
            self.init(value: offset < restingOffset ? 1 : 0, midpoint: 0.5)
            return
        }
        let scrolled = restingOffset - offset
        self.init(
            value: Double(min(max(scrolled / distance, 0), 1)),
            midpoint: Self.midpoint(for: distance)
        )
    }

    /// Opacity of everything that belongs to the expanded state — the large
    /// balance in the content, and the top bar's toolbar buttons. `1 → 0` over
    /// `0…midpoint`, i.e. the height of the content being faded.
    var expandedOpacity: Double {
        max(1 - value / midpoint, 0)
    }

    /// Opacity of everything that belongs to the collapsed state — the balance
    /// in the top bar and the bar's own opaque background. `0 → 1` over
    /// `midpoint…1`, i.e. the fixed `barFadeDistance`, so the bar's entrance is
    /// the same length however tall the content that just left was.
    var collapsedOpacity: Double {
        max((value - midpoint) / (1 - midpoint), 0)
    }

    /// Whether the top bar shows the balance instead of the toolbar buttons.
    /// Flips where both ramps are zero, so the swap itself is invisible.
    var isCollapsed: Bool {
        value >= midpoint
    }
}
