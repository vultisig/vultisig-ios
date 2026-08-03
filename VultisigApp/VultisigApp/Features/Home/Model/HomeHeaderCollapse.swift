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
/// read by exactly two leaves: the top bar itself, and the `headerCollapseFade`
/// modifier wrapped around the large balance inside the scroll content.
/// `HomeScreen` owns it in a plain `@State` and never reads it, so a scroll
/// never invalidates the tab content.
///
/// Two properties keep that per-frame write cheap:
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
        let progress = HeaderCollapseProgress(offset: offset, restingOffset: restingOffset)
        guard progress != self.progress(for: tab) else { return }

        switch tab {
        case .wallet: wallet = progress
        case .defi: defi = progress
        case .camera: break
        }
    }
}
