//
//  OffsetObservingScrollView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

enum ScrollViewNamespace {
    case local
    case scrollView
}

/// ScrollView with content offset reading capabilities
struct OffsetObservingScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators = true
    var contentInset: CGFloat
    var ns: ScrollViewNamespace
    @Binding var scrollOffset: CGFloat
    @ViewBuilder var content: () -> Content

    private let coordinateSpaceName = UUID()

    init(
        axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        contentInset: CGFloat = 0,
        ns: ScrollViewNamespace = .scrollView,
        scrollOffset: Binding<CGFloat>,
        content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.contentInset = contentInset
        self.ns = ns
        self._scrollOffset = scrollOffset
        self.content = content
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            contentContainer {
                insetView
                content()
                    .background(GeometryReader { proxy in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self, value: preferenceValue(proxy: proxy))
                    })
                insetView
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
    }
}

private extension OffsetObservingScrollView {
    @ViewBuilder
    func contentContainer<ScrollViewContent: View>(@ViewBuilder content: () -> ScrollViewContent) -> some View {
        if axes == .vertical {
            VStack(spacing: 0) { content() }
        } else {
            HStack(spacing: 0) { content() }
        }
    }
    var insetView: some View {
        if axes == .vertical {
            Color.clear.frame(height: contentInset)
        } else {
            Color.clear.frame(width: contentInset)
        }
    }

    func preferenceValue(proxy: GeometryProxy) -> CGFloat {
        let frame = proxyFrame(for: proxy)
        return axes == .vertical ? frame.minY : frame.minX
    }

    func proxyFrame(for proxy: GeometryProxy) -> CGRect {
        switch ns {
        case .local:
            proxy.frame(in: .named(coordinateSpaceName))
        case .scrollView:
            proxy.frame(in: .scrollView)
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    private static var lastUpdateTime: CFTimeInterval = 0
    private static let targetFrameRate: Double = 30
    private static var frameInterval: CFTimeInterval { 1.0 / targetFrameRate }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let newValue = nextValue()
        let currentTime = CACurrentMediaTime()

        // Only update if enough time has passed since the last update
        if currentTime - lastUpdateTime >= frameInterval {
            value += newValue
            lastUpdateTime = currentTime
        }
        // If not enough time has passed, keep the previous value (don't update)
    }
}
