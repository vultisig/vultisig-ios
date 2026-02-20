//
//  CrossPlatformToolbarModifier.swift
//  VultisigApp
//
//  Created by Assistant on 30/09/2025.
//

import SwiftUI

// MARK: - CustomToolbarItem

struct CustomToolbarItem {
    enum Placement {
        case leading
        case trailing
    }

    let placement: Placement
    let content: AnyView

    init<Content: View>(placement: Placement, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = AnyView(content())
    }
}

// MARK: - CustomToolbarItemsBuilder

@resultBuilder
struct CustomToolbarItemsBuilder {
    static func buildExpression(_ item: CustomToolbarItem) -> CustomToolbarItem {
        item
    }

    static func buildBlock(_ items: CustomToolbarItem...) -> [CustomToolbarItem] {
        items
    }

    static func buildOptional(_ item: [CustomToolbarItem]?) -> [CustomToolbarItem] {
        item ?? []
    }

    static func buildEither(first items: [CustomToolbarItem]) -> [CustomToolbarItem] {
        items
    }

    static func buildEither(second items: [CustomToolbarItem]) -> [CustomToolbarItem] {
        items
    }

    static func buildArray(_ items: [[CustomToolbarItem]]) -> [CustomToolbarItem] {
        items.flatMap { $0 }
    }

    static func buildBlock() -> [CustomToolbarItem] {
        []
    }
}

// MARK: - CrossPlatformToolbarModifier

struct CrossPlatformToolbarModifier: ViewModifier {
    private let items: [CustomToolbarItem]
    private let navigationTitle: String?
    private let ignoresTopEdge: Bool
    private let showsBackButton: Bool

    init(
        items: [CustomToolbarItem]? = nil,
        navigationTitle: String? = nil,
        ignoresTopEdge: Bool = false,
        showsBackButton: Bool = true
    ) {
        self.items = items ?? []
        self.navigationTitle = navigationTitle
        self.ignoresTopEdge = ignoresTopEdge
        self.showsBackButton = showsBackButton
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        MacOSToolbarView(
            items: items,
            navigationTitle: navigationTitle,
            ignoresTopEdge: ignoresTopEdge,
            showsBackButton: showsBackButton
        ) {
            content
        }
        #else
        IOSToolbarView(
            items: items,
            navigationTitle: navigationTitle
        ) {
            content
        }
        #endif
    }
}

// MARK: - View Extensions

extension View {
    /// Cross-platform toolbar modifier that works on both iOS and macOS
    /// - Parameters:
    ///   - navigationTitle: Optional title to display in the navigation bar/toolbar center
    ///   - ignoresTopEdge: On macOS, if true uses ZStack overlay (default), if false uses VStack layout
    ///   - showsBackButton: On macOS, if true shows back button automatically (default), iOS ignores this
    ///   - items: CustomToolbarItems builder for toolbar content
    func crossPlatformToolbar(
        navigationTitle: String? = nil,
        ignoresTopEdge: Bool = false,
        showsBackButton: Bool = true,
        @CustomToolbarItemsBuilder items: () -> [CustomToolbarItem]
    ) -> some View {
        modifier(CrossPlatformToolbarModifier(
            items: items(),
            navigationTitle: navigationTitle,
            ignoresTopEdge: ignoresTopEdge,
            showsBackButton: showsBackButton
        ))
    }

    /// Cross-platform toolbar modifier without custom items
    /// - Parameters:
    ///   - navigationTitle: Optional title to display in the navigation bar/toolbar center
    ///   - ignoresTopEdge: On macOS, if true uses ZStack overlay (default), if false uses VStack layout
    ///   - showsBackButton: On macOS, if true shows back button automatically (default), iOS ignores this
    func crossPlatformToolbar(
        navigationTitle: String? = nil,
        ignoresTopEdge: Bool = false,
        showsBackButton: Bool = true
    ) -> some View {
        modifier(CrossPlatformToolbarModifier(
            items: nil,
            navigationTitle: navigationTitle,
            ignoresTopEdge: ignoresTopEdge,
            showsBackButton: showsBackButton
        ))
    }

    /// Convenience method for toolbar with navigation title
    func crossPlatformToolbar(
        _ navigationTitle: String,
        ignoresTopEdge: Bool = false,
        showsBackButton: Bool = true,
        @CustomToolbarItemsBuilder items: () -> [CustomToolbarItem]
    ) -> some View {
        crossPlatformToolbar(
            navigationTitle: navigationTitle,
            ignoresTopEdge: ignoresTopEdge,
            showsBackButton: showsBackButton,
            items: items
        )
    }

    /// Convenience method for toolbar with navigation title and no custom items
    func crossPlatformToolbar(
        _ navigationTitle: String,
        ignoresTopEdge: Bool = false,
        showsBackButton: Bool = true
    ) -> some View {
        crossPlatformToolbar(
            navigationTitle: navigationTitle,
            ignoresTopEdge: ignoresTopEdge,
            showsBackButton: showsBackButton
        )
    }

}
