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
/// faded over **non-overlapping** halves of the progress: everything belonging
/// to the expanded state fades out over `0…0.5`, everything belonging to the
/// collapsed state fades in over `0.5…1`. `expandedOpacity` and
/// `collapsedOpacity` are therefore never both greater than zero, so the two
/// balances can never be legible at the same time — and because the whole
/// transition is a function of the scroll offset it scrubs with the drag and
/// reverses with it, instead of running on its own wall-clock timeline.
struct HeaderCollapseProgress: Equatable {
    /// Where the expanded state has finished fading out and the collapsed state
    /// starts fading in. The top bar swaps its contents exactly here, which is
    /// the one point where both ramps are zero.
    private static let midpoint: Double = 0.5

    /// Scroll distance, in points, over which the whole collapse plays out. The
    /// first half of it fades the large balance away as it travels towards the
    /// header edge; the second half brings the header balance in.
    static let defaultDistance: CGFloat = 110

    static let expanded = HeaderCollapseProgress(value: 0)

    /// `0` = fully expanded (large balance in the content), `1` = fully
    /// collapsed (balance in the top bar).
    let value: Double

    private init(value: Double) {
        self.value = value
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
            self.init(value: offset < restingOffset ? 1 : 0)
            return
        }
        let scrolled = restingOffset - offset
        self.init(value: Double(min(max(scrolled / distance, 0), 1)))
    }

    /// Opacity of everything that belongs to the expanded state — the large
    /// balance in the content, and the top bar's toolbar buttons. `1 → 0` over
    /// the first half of the collapse.
    var expandedOpacity: Double {
        max(1 - value / Self.midpoint, 0)
    }

    /// Opacity of everything that belongs to the collapsed state — the balance
    /// in the top bar and the bar's own opaque background. `0 → 1` over the
    /// second half of the collapse.
    var collapsedOpacity: Double {
        max((value - Self.midpoint) / (1 - Self.midpoint), 0)
    }

    /// Whether the top bar shows the balance instead of the toolbar buttons.
    /// Flips where both ramps are zero, so the swap itself is invisible.
    var isCollapsed: Bool {
        value >= Self.midpoint
    }
}
