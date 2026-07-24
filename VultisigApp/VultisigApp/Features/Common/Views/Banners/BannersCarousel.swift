//
//  BannerCarousel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "banners-carousel")

struct BannersCarousel<Banner: CarouselBannerType>: View {
    @Binding var banners: [Banner]
    let availableWidth: CGFloat
    /// Used for VStack spacing
    let paddingTop: CGFloat?
    var onBanner: (Banner) -> Void
    var onClose: (Banner) -> Void

    @State var currentIndex: Int = 0
    @State var scrollPosition: Int? = 0
    @State var bannersCount: Int = 0
    @State var bannersToRemove: Set<AnyHashable> = []
    @State private var timer: Timer?
    @State private var removalTask: Task<Void, Never>?
    @State var showCarousel: Bool = false

    @State var internalBanners: [Banner] = []

    var bannerWidth: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return availableWidth - spacing * 2
        } else {
            return BannerLayoutProperties.maxWidth
        }
        #else
        return BannerLayoutProperties.maxWidth
        #endif
    }

    var horizontalPadding: CGFloat {
        max((availableWidth - bannerWidth) / 2, BannerLayoutProperties.minimumPadding)
    }

    private let bannerHeight: CGFloat = 81
    private let spacing: CGFloat = 16
    private let indicatorsHeight: CGFloat = BannerLayoutProperties.indicatorsHeight

    var body: some View {
        ZStack {
            VStack(spacing: spacing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(internalBanners.indices, id: \.self) { index in
                            let banner = internalBanners[index]
                            let shouldRemove = bannersToRemove.contains(AnyHashable(banner.id)) && !banners.isEmpty
                            VStack {
                                CarouselBannerView(
                                    banner: banner,
                                    action: { onBanner(banner) },
                                    onClose: { removeBanner(banner) }
                                )
                                .frame(width: bannerWidth, height: bannerHeight, alignment: .leading)
                            }
                            .padding(.horizontal, spacing)
                            .frame(width: availableWidth, alignment: .center)
                            .opacity(shouldRemove ? 0 : 1)
                            .animation(.easeInOut(duration: 0.4), value: shouldRemove)
                            .scrollTransition { content, phase in
                                content
                                    .scaleEffect(y: phase.isIdentity ? 1 : 0.8)
                            }
                            .id(banner.id)
                        }
                    }
                    .scrollTargetLayout()
                    .animation(.easeInOut(duration: 0.3), value: internalBanners.count)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPosition, anchor: .center)
                .scrollIndicators(.never)

                VaultBannerCarouselIndicators(
                    currentIndex: $currentIndex,
                    bannersCount: $bannersCount
                )
                .transition(.verticalGrowAndFade)
                .animation(.easeInOut, value: bannersCount)
                .showIf(bannersCount > 1)
            }
            .unwrap(paddingTop) { $0.padding(.top, $1) }
            .transition(.verticalGrowAndFade)
            .showIf(showCarousel)
        }
        .onLoad {
            internalBanners = banners
        }
        .onChange(of: banners) { _, newValue in
            guard Set(internalBanners) != Set(newValue) else { return }
            internalBanners = banners
        }
        .onChange(of: internalBanners) { _, newValue in
            updateBannersCount(newValue.count)
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
            removalTask?.cancel()
            removalTask = nil
        }
        .onChange(of: currentIndex) {
            guard currentIndex >= 0 && currentIndex < internalBanners.count else { return }
            // Sync the scroll position to the active index only when it actually
            // differs. A no-op write still emits a graph mutation, which — if it
            // lands mid render-commit — can reenter AppKit's constraint cycle and
            // crash on macOS. Guarding it keeps reciprocal index/scroll syncs from
            // ping-ponging.
            guard scrollPosition != currentIndex else { return }
            withAnimation {
                scrollPosition = currentIndex
            }
        }
        .onChange(of: scrollPosition) {
            guard let newScrollPosition = scrollPosition else { return }
            // Only adopt a user-driven scroll change when it moves us to a new
            // index; otherwise this would write back the value the index handler
            // just set and re-trigger the cycle.
            guard currentIndex != newScrollPosition else { return }
            currentIndex = newScrollPosition
            // Restart the auto-advance timer outside any animation block: nesting
            // a timer (re)start inside withAnimation runs an NSAnimationContext at
            // the same time a publisher/runloop tick is committing layout.
            startTimer()
        }
    }

    func removeBanner(_ banner: Banner) {
        stopTimer()

        if bannersCount == 1 {
            updateBannersCount(0)
        }

        guard let indexToRemove = internalBanners.firstIndex(where: { $0.id == banner.id }) else {
            logger.warning("Banner not found for removal")
            return
        }

        // Calculate the new current index before removal
        let newCurrentIndex = BannersCarouselIndex.afterRemoval(
            removedIndex: indexToRemove,
            currentIndex: currentIndex,
            countBeforeRemoval: internalBanners.count
        )

        // Start the removal animation
        _ = withAnimation(.easeInOut(duration: 0.4)) {
            bannersToRemove.insert(AnyHashable(banner.id))
        }

        // Wait for removal animation to complete, then update the data. A
        // cancellable task (cancelled in stopTimer/onDisappear) prevents a stale
        // closure from mutating state after the view is torn down.
        removalTask?.cancel()
        removalTask = delayedTask(after: .milliseconds(400)) {
            // Remove the banner from the array
            internalBanners.removeAll { $0.id == banner.id }
            bannersToRemove.remove(AnyHashable(banner.id))

            // Update indices without animation to prevent conflicts. Guard each
            // write so an unchanged value never emits a graph mutation.
            let targetIndex = internalBanners.isEmpty
                ? 0
                : min(max(0, newCurrentIndex), internalBanners.count - 1)
            if currentIndex != targetIndex {
                currentIndex = targetIndex
            }
            if scrollPosition != targetIndex {
                scrollPosition = targetIndex
            }

            if !internalBanners.isEmpty {
                startTimer()
            }

            // Notify parent that banner was removed
            onClose(banner)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            let nextIndex = BannersCarouselIndex.next(after: currentIndex, count: bannersCount)
            // Guard the auto-advance write: if there's nothing to advance to
            // (e.g. a single banner) the value is unchanged, so skip the mutation
            // entirely rather than emit a no-op graph update from a runloop tick.
            guard nextIndex != currentIndex else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex = nextIndex
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateBannersCount(_ count: Int) {
        let shouldShow = count > 0
        withAnimation(.easeInOut) {
            showCarousel = shouldShow
            bannersCount = count
        }
    }
}

/// Pure index math for the carousel, extracted so the wrap-around and
/// post-removal logic can be unit-tested without a view host.
enum BannersCarouselIndex {
    /// Index the auto-advance timer should move to next, wrapping back to the
    /// start after the last banner. Returns `current` unchanged when there is
    /// nothing to advance to (zero or one banner) so callers can no-op the write.
    static func next(after current: Int, count: Int) -> Int {
        guard count > 1 else { return current }
        return current < count - 1 ? current + 1 : 0
    }

    /// Index that should become current after the banner at `removedIndex` is
    /// removed, given the count *before* removal.
    static func afterRemoval(removedIndex: Int, currentIndex: Int, countBeforeRemoval: Int) -> Int {
        guard countBeforeRemoval > 1 else { return 0 }

        if removedIndex < currentIndex {
            // Removing a banner before the current one shifts us back by one.
            return currentIndex - 1
        }

        if removedIndex == currentIndex {
            // Removing the current banner: if it was last, step back; otherwise
            // the next banner slides into this slot, so the index is unchanged.
            return removedIndex == countBeforeRemoval - 1 ? max(0, currentIndex - 1) : currentIndex
        }

        // Removing a banner after the current one leaves the index unchanged.
        return currentIndex
    }
}

#Preview {
    @Previewable @State var banners = [VaultBannerType.upgradeVault, .backupVault, .followVultisig]

    BannersCarousel(
        banners: $banners,
        availableWidth: 500,
        paddingTop: nil,
        onBanner: { _ in },
        onClose: { _ in }
    )
}
