//
//  HomeHeaderCollapse.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/08/2025.
//

import Foundation

/// Shared collapse progress for the vault-home top bar, one value per tab.
///
/// Written from the scroll views' geometry reader on **every layout pass**, and
/// read only by leaves: the top bar's trailing slot and background, and the
/// `headerCollapseFade` modifier wrapped around each large balance inside the
/// scroll content. `HomeScreen` owns it in a plain `@State` and never reads it,
/// and neither tab screen reads it either, so a scroll never invalidates a
/// content tree — every observer re-applies an opacity to an already-built
/// subtree. (Being one `ObservableObject`, a change on one tab does wake the
/// other tab's fade modifier as well; that is one redundant opacity write per
/// transition frame, not a rebuild.)
///
/// Two properties keep the per-frame write cheap:
/// - `update` compares before it publishes, and
/// - the progress saturates at `0`/`1` outside a
///   `HeaderCollapseProgress.defaultDistance`-point window, so all but that
///   window of a scroll publishes nothing at all.
///
/// Both tabs are stored separately because both screens stay alive inside the
/// tab view — each one keeps its own scroll position, and the top bar reads
/// whichever tab is active.
@MainActor
final class HomeHeaderCollapse: ObservableObject {
    @Published private(set) var wallet: HeaderCollapseProgress = .expanded
    @Published private(set) var defi: HeaderCollapseProgress = .expanded

    func progress(for tab: HomeTab) -> HeaderCollapseProgress {
        switch tab {
        case .wallet: wallet
        case .defi: defi
        case .camera: .expanded
        }
    }

    /// - Parameters:
    ///   - tab: the tab whose scroll view produced the offset.
    ///   - offset: the scroll content's `minY` in the scroll view's space.
    ///   - restingOffset: that value at scroll position zero (the top inset).
    func update(tab: HomeTab, offset: CGFloat, restingOffset: CGFloat) {
        // Per-tab distance: the ramp has to match the height of whatever that
        // tab fades, or the content empties before it has left the screen.
        let progress = HeaderCollapseProgress(
            offset: offset,
            restingOffset: restingOffset,
            distance: HeaderCollapseProgress.distance(for: tab)
        )
        guard progress != self.progress(for: tab) else { return }

        switch tab {
        case .wallet: wallet = progress
        case .defi: defi = progress
        case .camera: break
        }
    }
}
