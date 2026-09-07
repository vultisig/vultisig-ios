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
            guard scrollOffset != value else { return }
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

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Reduction combines one preference tree at a time. A shared clock here
        // drops values from unrelated scroll views and can replace an offset
        // with the default value. Keep reduction independent of time/instances;
        // the picker handles scroll-settle debouncing after receiving offsets.
        value += nextValue()
    }
}
