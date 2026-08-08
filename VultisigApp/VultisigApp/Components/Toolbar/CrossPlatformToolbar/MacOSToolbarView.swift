//
//  MacOSToolbarView.swift
//  VultisigApp
//
//  Created by Assistant on 30/09/2025.
//

import SwiftUI

#if os(macOS)
struct MacOSToolbarView<Content: View>: View {
    let items: [CustomToolbarItem]
    let navigationTitle: String?
    let ignoresTopEdge: Bool
    let showsBackButton: Bool
    let content: Content

    @Environment(\.dismiss) var dismiss
    @Environment(\.screenBackgroundType) private var screenBackgroundType

    init(
        items: [CustomToolbarItem],
        navigationTitle: String?,
        ignoresTopEdge: Bool = true,
        showsBackButton: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.items = items
        self.navigationTitle = navigationTitle
        self.ignoresTopEdge = ignoresTopEdge
        self.showsBackButton = showsBackButton
        self.content = content()
    }

    var body: some View {
        if ignoresTopEdge {
            content
                .overlay(toolbarContent, alignment: .top)
                // Workaround to remove translucent window toolbar on MacOS Tahoe (Liquid glass)
                .padding(.top, 1)
        } else {
            // VStack layout approach
            VStack(spacing: 0) {
                // macOS toolbar
                toolbarContent
                    .background(barBackground)

                // Content below toolbar
                content
            }
        }
    }

    /// The bar fills itself only over a screen that is a flat colour anyway.
    ///
    /// `bgPrimary` behind the bar is invisible on a `.plain` screen and a seam on
    /// any other: over a gradient it cuts an opaque band across the top sixty
    /// points, and over `.clear` it paints a background the caller asked not to
    /// have. The screen already draws its own background edge to edge, so
    /// stepping out of the way is all this has to do.
    @ViewBuilder
    private var barBackground: some View {
        switch screenBackgroundType {
        case .plain:
            Theme.colors.bgPrimary
        case .gradient, .clear:
            Color.clear
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 0) {
            // Leading
            HStack(spacing: 8) {
                if showsBackButton {
                    ToolbarButton(image: .chevronRight, action: {
                        dismiss()
                    })
                    .rotationEffect(.radians(.pi))
                }

                ForEach(Array(leadingItems.enumerated()), id: \.offset) { _, item in
                    item.content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center
            if !centerItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(centerItems.enumerated()), id: \.offset) { _, item in
                        item.content
                    }
                }
                .layoutPriority(1)
            } else if let navigationTitle {
                Text(navigationTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodyLMedium)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Trailing
            HStack(spacing: 8) {
                ForEach(Array(trailingItems.enumerated()), id: \.offset) { _, item in
                    item.content
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 60)
        .padding(.horizontal, 16)
    }

    private var leadingItems: [CustomToolbarItem] {
        items.filter { $0.placement == .leading }
    }

    private var centerItems: [CustomToolbarItem] {
        items.filter { $0.placement == .center }
    }

    private var trailingItems: [CustomToolbarItem] {
        items.filter { $0.placement == .trailing }
    }
}
#endif
