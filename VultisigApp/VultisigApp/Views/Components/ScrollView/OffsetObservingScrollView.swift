//
//  OffsetObservingScrollView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

/// ScrollView with content offset reading capabilities
struct OffsetObservingScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators = true
    var contentInset: CGFloat
    @Binding var scrollOffset: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        contentInset: CGFloat = 0,
        scrollOffset: Binding<CGFloat>,
        content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.contentInset = contentInset
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
                    }.frame(height: 0))
                insetView
            }
        }
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
        let frame = proxy.frame(in: .scrollView)
        return axes == .vertical ? frame.minY : frame.minX
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}
