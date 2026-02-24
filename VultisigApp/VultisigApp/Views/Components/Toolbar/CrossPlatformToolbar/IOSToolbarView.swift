//
//  IOSToolbarView.swift
//  VultisigApp
//
//  Created by Assistant on 30/09/2025.
//

import SwiftUI

#if !os(macOS)
struct IOSToolbarView<Content: View>: View {
    let items: [CustomToolbarItem]
    let navigationTitle: String?
    let content: Content

    @Environment(\.isSheetPresented) var isSheetPresented

    init(
        items: [CustomToolbarItem],
        navigationTitle: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.items = items
        self.navigationTitle = navigationTitle
        self.content = content()
    }

    var body: some View {
        contentContainer
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                trailingPlainToolbarItems
                
                ToolbarItemGroup(placement: .cancellationAction) {
                    ForEach(Array(leadingItems.enumerated()), id: \.offset) { _, item in
                        item.content
                            .environment(\.isNativeToolbarItem, true)
                    }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
                    ForEach(Array(trailingGlassItems.enumerated()), id: \.offset) { _, item in
                        item.content
                            .environment(\.isNativeToolbarItem, true)
                    }
                }
            }
    }

    @ToolbarContentBuilder
    private var trailingPlainToolbarItems: some ToolbarContent {
        if #available(iOS 26.0, *) {
            trailingToolbarItems
                .sharedBackgroundVisibility(.hidden)
        } else {
            trailingToolbarItems
        }
    }
    
    private var trailingToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .confirmationAction) {
            ForEach(Array(trailingPlainItems.enumerated()), id: \.offset) { _, item in
                item.content
                    .environment(\.isNativeToolbarItem, true)
            }
        }
    }

    @ViewBuilder
    var contentContainer: some View {
        // Wrap sheet content on NavigationStack to make navigation title visible
        if isSheetPresented, navigationTitle != nil {
            NavigationStack {
                contentWithTitle
                    .background(Theme.colors.bgPrimary.ignoresSafeArea())
            }
        } else {
            contentWithTitle
        }
    }

    var contentWithTitle: some View {
        content
            .unwrap(navigationTitle) { $0.navigationTitle($1) }
            .navigationBarTitleDisplayMode(.inline)
    }

    private var leadingItems: [CustomToolbarItem] {
        items.filter { $0.placement == .leading }
    }

    private var trailingGlassItems: [CustomToolbarItem] {
        items.filter { $0.placement == .trailing && !$0.hideSharedBackground }
    }

    private var trailingPlainItems: [CustomToolbarItem] {
        items.filter { $0.placement == .trailing && $0.hideSharedBackground }
    }
}
#endif
