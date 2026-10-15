//
//  HomeTabPager.swift
//  VultisigApp
//

import SwiftUI

/// The home's tabs side by side in one horizontally paged scroll view: the user
/// swipes between them, and picking a tab in the bar slides there.
///
/// Both pages stay alive, as they did inside a `TabView`, so each keeps its own
/// scroll position.
struct HomeTabPager<Content: View>: View {
    @Binding var selectedTab: HomeTab
    let tabs: [HomeTab]
    let onAccessory: () -> Void
    @ViewBuilder let content: (HomeTab) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledTab: HomeTab?
    /// Held in a plain `@State` and never read here: it is written on every
    /// frame of a swipe, and only the bar observes it, so a swipe never
    /// rebuilds the pages.
    @State private var progress = HomePagerProgress()

    // 40pt bar bottom-padding + 64pt bar pill + 16pt visual breathing room.
    private let barReservedHeight: CGFloat = 120
    /// Lands a little past the tab and settles back, which the pill's stretch
    /// and overshoot ride on.
    private let tabSwitchAnimation = Animation.spring(response: 0.5, dampingFraction: 0.72)

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        content(tab)
                            // The bar is an overlay, so nothing reserves room
                            // for it; each page publishes its own inset.
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Color.clear.frame(height: barReservedHeight)
                            }
                            .containerRelativeFrame(.horizontal)
                            // Only the page on screen is readable or tappable, as in a `TabView`.
                            .accessibilityHidden(tab != selectedTab)
                            .allowsHitTesting(tab == selectedTab)
                            .id(tab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledTab)
            .scrollIndicators(.hidden)
            .trackPageProgress(progress, restingIndex: index(of: selectedTab))

            HomePagerTabBar(
                selectedTab: $selectedTab,
                tabs: tabs,
                progress: progress,
                onAccessory: onAccessory
            )
        }
        // Only the bottom: the pages still need the top inset, which a
        // `TabView` used to hand them.
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { scrolledTab = selectedTab }
        .onChange(of: scrolledTab) { _, tab in
            guard let tab, tab != selectedTab else { return }
            selectedTab = tab
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab != scrolledTab else { return }
            guard !reduceMotion else {
                scrolledTab = tab
                return
            }
            withAnimation(tabSwitchAnimation) {
                scrolledTab = tab
            }
        }
    }

    private func index(of tab: HomeTab) -> Int {
        tabs.firstIndex(of: tab) ?? 0
    }
}

/// How far the pager has travelled, in pages: `0` on the first page, `1` on the
/// second, fractional in between.
@MainActor
final class HomePagerProgress: ObservableObject {
    @Published private(set) var position: CGFloat = 0

    func update(_ newPosition: CGFloat) {
        guard newPosition != position else { return }
        position = newPosition
    }
}

/// The bar, split out so that it alone re-evaluates as the pager moves.
private struct HomePagerTabBar: View {
    @Binding var selectedTab: HomeTab
    let tabs: [HomeTab]
    @ObservedObject var progress: HomePagerProgress
    let onAccessory: () -> Void

    private let overshoot: CGFloat = 0.15

    var body: some View {
        VultiTabBarControls(
            selectedItem: $selectedTab,
            items: tabs,
            indicatorPosition: indicatorPosition,
            accessory: .camera,
            onAccessory: onAccessory
        )
    }

    /// A little room past either end, so a springy landing overshoots.
    private var indicatorPosition: CGFloat {
        min(max(progress.position, -overshoot), CGFloat(tabs.count - 1) + overshoot)
    }
}

/// Runs `action` whenever `page` becomes the visible tab, or the header needs
/// it fresh while hidden (`homeAlwaysFreshPages`), at most once per `interval`
/// — what `onAppear` did for each tab inside a `TabView`, where the pager now
/// keeps both pages on screen.
private struct HomePageVisibleRefresh: ViewModifier {
    let page: HomeTab
    let interval: TimeInterval
    let action: () -> Void

    @Environment(\.homeSelectedTab) private var selectedTab
    @Environment(\.homeAlwaysFreshPages) private var alwaysFreshPages
    @State private var isOnScreen = false
    @State private var lastRun: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                isOnScreen = true
                runIfVisible()
            }
            .onDisappear { isOnScreen = false }
            .onChange(of: selectedTab) { _, _ in runIfVisible() }
            .onChange(of: alwaysFreshPages) { _, _ in runIfVisible() }
    }

    private func runIfVisible() {
        guard isOnScreen, selectedTab == page || alwaysFreshPages.contains(page) else { return }
        let now = Date()
        if let lastRun, now.timeIntervalSince(lastRun) < interval { return }
        lastRun = now
        action()
    }
}

extension View {
    /// See `HomePageVisibleRefresh`.
    func refreshWhenVisible(on page: HomeTab, interval: TimeInterval, action: @escaping () -> Void) -> some View {
        modifier(HomePageVisibleRefresh(page: page, interval: interval, action: action))
    }
}

private extension View {
    /// Feeds the pager's live position to `progress`. Before iOS 18 the scroll
    /// geometry is not observable, so the indicator steps to `restingIndex`
    /// instead of tracking the drag.
    @ViewBuilder
    func trackPageProgress(_ progress: HomePagerProgress, restingIndex: Int) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x / max(geometry.containerSize.width, 1)
            } action: { _, position in
                progress.update(position)
            }
        } else {
            onChange(of: restingIndex, initial: true) { _, index in
                progress.update(CGFloat(index))
            }
        }
    }
}
