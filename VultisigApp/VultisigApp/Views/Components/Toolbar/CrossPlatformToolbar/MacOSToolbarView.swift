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
                    .background(Theme.colors.bgPrimary)

                // Content below toolbar
                content
            }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 0) {
            // Leading
            HStack(spacing: 8) {
                if showsBackButton {
                    ToolbarButton(image: "chevron-right", action: {
                        dismiss()
                    })
                    .rotationEffect(.radians(.pi))
                }

                ForEach(Array(leadingItems.enumerated()), id: \.offset) { _, item in
                    item.content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Title
            if let navigationTitle {
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

    private var trailingItems: [CustomToolbarItem] {
        items.filter { $0.placement == .trailing }
    }
}
#endif
