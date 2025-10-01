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
            // ZStack overlay approach (existing behavior)
            ZStack(alignment: .top) {
                // Content
                content
                
                // macOS toolbar with transparent background
                toolbarContent
            }
        } else {
            // VStack layout approach
            VStack(spacing: 0) {
                // macOS toolbar
                toolbarContent
                
                // Content below toolbar
                content
            }
        }
    }
    
    private var toolbarContent: some View {
        HStack(alignment: .center) {
            // Leading items with automatic back button
            HStack(spacing: 8) {
                // Automatic back button
                if showsBackButton {
                    ToolbarButton(image: "chevron-right", action: { dismiss() })
                        .rotationEffect(.radians(.pi))
                }
                
                // Custom leading items
                ForEach(Array(leadingItems.enumerated()), id: \.offset) { _, item in
                    item.content
                }
            }
            
            Spacer()
            
            // Navigation title in the center
            if let navigationTitle {
                Text(navigationTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Trailing items
            ForEach(Array(trailingItems.enumerated()), id: \.offset) { _, item in
                item.content
            }
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
