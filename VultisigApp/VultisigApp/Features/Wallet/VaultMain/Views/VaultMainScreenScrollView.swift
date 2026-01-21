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
    var contentInset: CGFloat
    @Binding var scrollOffset: CGFloat
    @ViewBuilder var content: () -> Content

    private let coordinateSpaceName = UUID()
    
    // Throttling state for 15fps
    @State private var lastUpdateTime: CFTimeInterval = 0
    @State private var pendingValue: CGFloat?
    @State private var throttleTimer: Timer?
    private let frameInterval: TimeInterval = 1.0 / 5.0 // 5fps
    
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
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: preferenceValue(proxy: proxy)) { _, newValue in
                                    throttledUpdateOffset(newValue)
                                }
                        }
                    )
                insetView
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .onDisappear {
            // Clean up timer when view disappears
            throttleTimer?.invalidate()
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
    
    func throttledUpdateOffset(_ newValue: CGFloat) {
        let currentTime = CACurrentMediaTime()
        
        // Store the latest value
        pendingValue = newValue
        
        // If enough time has passed since last update, update immediately
        if currentTime - lastUpdateTime >= frameInterval {
            scrollOffset = newValue
            lastUpdateTime = currentTime
            pendingValue = nil
            return
        }
        
        // Otherwise, schedule an update if we haven't already
        if throttleTimer == nil {
            let remainingTime = frameInterval - (currentTime - lastUpdateTime)
            throttleTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { _ in
                if let value = pendingValue {
                    scrollOffset = value
                    lastUpdateTime = CACurrentMediaTime()
                    pendingValue = nil
                }
                throttleTimer = nil
            }
        }
    }
}
