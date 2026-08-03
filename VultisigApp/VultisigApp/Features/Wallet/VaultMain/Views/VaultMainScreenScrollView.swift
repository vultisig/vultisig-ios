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
    /// Called with the content's `minY` in the scroll view's coordinate space
    /// once per layout pass — i.e. every frame while the user drags.
    ///
    /// It has to stay cheap, and it must not write view state: a `@State` write
    /// here invalidates this view's body, which re-invokes `content()` — the
    /// entire screen's content tree — at display rate. The offset used to be
    /// published through a `@Binding` and needed a throttle in front of it for
    /// exactly that reason; its only consumer now is the header-collapse
    /// progress, which compares before it publishes and publishes to leaf
    /// views only, so the raw per-frame value can be handed over as-is.
    var onOffsetChange: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    init(
        axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        onOffsetChange: @escaping (CGFloat) -> Void,
        content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.onOffsetChange = onOffsetChange
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
                                    onOffsetChange(newValue)
                                }
                        }
                    )
                insetView(length: bottomInset)
            }
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
