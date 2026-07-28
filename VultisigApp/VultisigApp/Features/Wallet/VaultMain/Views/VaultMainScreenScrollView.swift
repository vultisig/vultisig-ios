//
//  VaultMainScreenScrollView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/10/2025.
//

import SwiftUI

/// ScrollView with content offset reading capabilities
struct VaultMainScreenScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators = true
    var topInset: CGFloat
    var bottomInset: CGFloat
    @Binding var scrollOffset: CGFloat
    @ViewBuilder var content: () -> Content

    /// Throttle bookkeeping lives in a reference box rather than in `@State`
    /// scalars. The offset reader below fires once per layout pass — i.e. every
    /// frame while the user drags — and writing `@State` there would invalidate
    /// this view's body, re-invoking `content()` (the entire wallet content
    /// tree) at display rate. That defeated the whole point of the throttle:
    /// only the `scrollOffset` binding was rate-limited, the expensive rebuild
    /// was not. Mutating the box's properties is invisible to SwiftUI, so the
    /// only re-render left is the throttled binding write itself.
    @State private var throttle = ScrollOffsetThrottle(interval: 1.0 / 5.0)

    init(
        axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        scrollOffset: Binding<CGFloat>,
        content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.topInset = topInset
        self.bottomInset = bottomInset
        self._scrollOffset = scrollOffset
        self.content = content
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            contentContainer {
                insetView(length: topInset)
                content()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: preferenceValue(proxy: proxy)) { _, newValue in
                                    throttle.submit(newValue) { scrollOffset = $0 }
                                }
                        }
                    )
                insetView(length: bottomInset)
            }
        }
        .onDisappear {
            throttle.cancel()
        }
    }
}

private extension VaultMainScreenScrollView {
    @ViewBuilder
    func contentContainer<ScrollViewContent: View>(@ViewBuilder content: () -> ScrollViewContent) -> some View {
        if axes == .vertical {
            VStack(spacing: 0) { content() }
        } else {
            HStack(spacing: 0) { content() }
        }
    }

    @ViewBuilder
    func insetView(length: CGFloat) -> some View {
        if axes == .vertical {
            Color.clear.frame(height: length)
        } else {
            Color.clear.frame(width: length)
        }
    }

    func preferenceValue(proxy: GeometryProxy) -> CGFloat {
        let frame = proxy.frame(in: .scrollView)
        return axes == .vertical ? frame.minY : frame.minX
    }
}

/// Leading-edge throttle for the scroll offset, with a trailing emission so the
/// last value of a burst is never dropped.
///
/// Deliberately a class: it is held in a single `@State` so the per-frame
/// bookkeeping never invalidates the owning view's body.
private final class ScrollOffsetThrottle {
    private let interval: TimeInterval
    private var lastEmitTime: CFTimeInterval = 0
    private var pendingValue: CGFloat?
    private var timer: Timer?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Emits `value` immediately when `interval` has elapsed since the last
    /// emission, otherwise schedules a single trailing emission of the newest
    /// value seen in the meantime.
    func submit(_ value: CGFloat, emit: @escaping (CGFloat) -> Void) {
        let now = CACurrentMediaTime()
        pendingValue = value

        if now - lastEmitTime >= interval {
            flush(now: now, emit: emit)
            return
        }

        guard timer == nil else { return }

        let trailing = Timer(timeInterval: interval - (now - lastEmitTime), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            self.flush(now: CACurrentMediaTime(), emit: emit)
        }
        timer = trailing
        // `.common` mode, not the default one: the default run loop mode is
        // suspended for the whole duration of a scroll drag, so a timer
        // scheduled there never fires while the finger is down — exactly when
        // the trailing update is needed.
        RunLoop.main.add(trailing, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func flush(now: CFTimeInterval, emit: (CGFloat) -> Void) {
        guard let value = pendingValue else { return }
        pendingValue = nil
        lastEmitTime = now
        emit(value)
    }
}
