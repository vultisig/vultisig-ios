//
//  HomeFloatingHeader.swift
//  VultisigApp
//

import SwiftUI

/// Where each home page keeps room for the shared header.
struct HomeHeaderSlotKey: PreferenceKey {
    static let defaultValue: [HomeTab: Anchor<CGRect>] = [:]

    static func reduce(value: inout [HomeTab: Anchor<CGRect>], nextValue: () -> [HomeTab: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension EnvironmentValues {
    /// Height of the floating home header, so each page's slot matches it.
    @Entry var homeHeaderHeight: CGFloat = 0
    /// How much of the header's balance is drawn, blended from both pages'
    /// collapse progress.
    @Entry var homeHeaderBalanceOpacity: Double = 1
}

/// The room a page keeps at the top of its scroll content for the header that
/// floats above both pages. It scrolls with the page, and the header follows it.
struct HomeHeaderSlot: View {
    let page: HomeTab

    @Environment(\.homeHeaderHeight) private var height

    var body: some View {
        Color.clear
            .frame(height: height)
            .anchorPreference(key: HomeHeaderSlotKey.self, value: .bounds) { [page: $0] }
    }
}

/// Draws the home header once, above the pager, at its slot on whichever page
/// is showing. Mid-swipe it blends between the two slots, so the header never
/// slides and is never drawn twice, even when the pages rest at different
/// scroll heights.
struct HomeFloatingHeader<Header: View>: View {
    let slots: [HomeTab: Anchor<CGRect>]
    @ObservedObject var collapse: HomeHeaderCollapse
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let header: () -> Header

    var body: some View {
        GeometryReader { proxy in
            let placement = HomeHeaderPlacement(
                wallet: slots[.wallet].map { proxy[$0] },
                defi: slots[.defi].map { proxy[$0] },
                width: proxy.size.width,
                walletBalanceOpacity: collapse.progress(for: .wallet).expandedOpacity,
                defiBalanceOpacity: collapse.progress(for: .defi).expandedOpacity
            )
            header()
                .environment(\.homeHeaderBalanceOpacity, placement.balanceOpacity)
                .frame(width: proxy.size.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
                .offset(y: placement.minY)
                .headerCollapseOpacity(placement.presence)
        }
    }
}

/// Where the floating header goes for the current pager and scroll positions.
private struct HomeHeaderPlacement {
    let minY: CGFloat
    /// Fades the header in and out with a slot that is not laid out, which a
    /// lazy page does once its top has scrolled far away.
    let presence: Double
    let balanceOpacity: Double

    init(
        wallet: CGRect?,
        defi: CGRect?,
        width: CGFloat,
        walletBalanceOpacity: Double,
        defiBalanceOpacity: Double
    ) {
        let progress = Self.progress(wallet: wallet, defi: defi, width: width)
        let mix = { (from: CGFloat, to: CGFloat) in from + (to - from) * progress }

        minY = mix(wallet?.minY ?? defi?.minY ?? 0, defi?.minY ?? wallet?.minY ?? 0)
        presence = Double(mix(wallet == nil ? 0 : 1, defi == nil ? 0 : 1))
        balanceOpacity = Double(mix(CGFloat(walletBalanceOpacity), CGFloat(defiBalanceOpacity)))
    }

    /// `0` with Wallet on screen, `1` with DeFi, read off whichever slot is laid out.
    private static func progress(wallet: CGRect?, defi: CGRect?, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        if let wallet { return min(max(-wallet.minX / width, 0), 1) }
        if let defi { return min(max(1 - defi.minX / width, 0), 1) }
        return 0
    }
}
