//
//  CrossPlatformToolbarModifier.swift
//  VultisigApp
//
//  Created by Assistant on 30/09/2025.
//

import SwiftUI

// MARK: - CustomToolbarItem

public struct CustomToolbarItem {
    public enum Placement {
        case leading
        case trailing
    }

    public let placement: Placement
    public let content: AnyView
    public let hideSharedBackground: Bool

    public init<Content: View>(
        placement: Placement,
        hideSharedBackground: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.hideSharedBackground = hideSharedBackground
        self.content = AnyView(content())
    }
}

// MARK: - CustomToolbarItemsBuilder

@resultBuilder
public struct CustomToolbarItemsBuilder {
    public static func buildExpression(_ item: CustomToolbarItem) -> CustomToolbarItem {
        item
    }

    public static func buildBlock(_ items: CustomToolbarItem...) -> [CustomToolbarItem] {
        items
    }

    public static func buildOptional(_ item: [CustomToolbarItem]?) -> [CustomToolbarItem] {
        item ?? []
    }

    public static func buildEither(first items: [CustomToolbarItem]) -> [CustomToolbarItem] {
        items
    }

    public static func buildEither(second items: [CustomToolbarItem]) -> [CustomToolbarItem] {
        items
    }

    public static func buildArray(_ items: [[CustomToolbarItem]]) -> [CustomToolbarItem] {
        items.flatMap { $0 }
    }

    public static func buildBlock() -> [CustomToolbarItem] {
        []
    }
}

// MARK: - CrossPlatformToolbarModifier

public struct CrossPlatformToolbarModifier: ViewModifier {
    private let items: [CustomToolbarItem]
    private let navigationTitle: String?
    private let ignoresTopEdge: Bool
    private let showsBackButton: Bool

    public init(
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

    public func body(content: Content) -> some View {
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

// MARK: - MacOSWindowModifier

public struct MacOSWindowModifier: ViewModifier {
    private let maxWidth: CGFloat?
    private let minHeight: CGFloat?
    private let topPadding: CGFloat
    private let horizontalPadding: CGFloat

    public init(
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        topPadding: CGFloat = 0,
        horizontalPadding: CGFloat = 0
    ) {
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.topPadding = topPadding
        self.horizontalPadding = horizontalPadding
    }

    public func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(maxWidth: maxWidth, minHeight: minHeight)
            .padding(.top, topPadding)
            .padding(.horizontal, horizontalPadding)
        #else
        content
        #endif
    }
}

// MARK: - View Extensions

public extension View {
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

    /// macOS-specific window sizing and padding modifier
    /// - Parameters:
    ///   - maxWidth: Maximum width for macOS window
    ///   - minHeight: Minimum height for macOS window
    ///   - topPadding: Additional top padding for macOS
    ///   - horizontalPadding: Additional horizontal padding for macOS
    func macOSWindow(
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        topPadding: CGFloat = 0,
        horizontalPadding: CGFloat = 0
    ) -> some View {
        modifier(MacOSWindowModifier(
            maxWidth: maxWidth,
            minHeight: minHeight,
            topPadding: topPadding,
            horizontalPadding: horizontalPadding
        ))
    }
}
