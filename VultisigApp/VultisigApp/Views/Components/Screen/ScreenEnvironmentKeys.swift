//
//  ScreenEnvironmentKeys.swift
//  VultisigApp
//

import SwiftUI

// MARK: - ScreenBackgroundType

enum ScreenBackgroundType {
    case plain
    case gradient
    case clear
}

// MARK: - Environment Keys

private struct ScreenTitleKey: EnvironmentKey {
    static let defaultValue: String = ""
}

private struct ScreenEdgeInsetsKey: EnvironmentKey {
    static let defaultValue: ScreenEdgeInsets = .noInsets
}

private struct ScreenBackgroundTypeKey: EnvironmentKey {
    static let defaultValue: ScreenBackgroundType = .plain
}

private struct ScreenNavigationBarHiddenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct ScreenBackButtonHiddenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct ScreenIgnoresTopEdgeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct ScreenToolbarItemsKey: EnvironmentKey {
    static let defaultValue: [CustomToolbarItem] = []
}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    var screenTitle: String {
        get { self[ScreenTitleKey.self] }
        set { self[ScreenTitleKey.self] = newValue }
    }

    var screenEdgeInsets: ScreenEdgeInsets {
        get { self[ScreenEdgeInsetsKey.self] }
        set { self[ScreenEdgeInsetsKey.self] = newValue }
    }

    var screenBackgroundType: ScreenBackgroundType {
        get { self[ScreenBackgroundTypeKey.self] }
        set { self[ScreenBackgroundTypeKey.self] = newValue }
    }

    var screenNavigationBarHidden: Bool {
        get { self[ScreenNavigationBarHiddenKey.self] }
        set { self[ScreenNavigationBarHiddenKey.self] = newValue }
    }

    var screenBackButtonHidden: Bool {
        get { self[ScreenBackButtonHiddenKey.self] }
        set { self[ScreenBackButtonHiddenKey.self] = newValue }
    }

    var screenIgnoresTopEdge: Bool {
        get { self[ScreenIgnoresTopEdgeKey.self] }
        set { self[ScreenIgnoresTopEdgeKey.self] = newValue }
    }

    var screenToolbarItems: [CustomToolbarItem] {
        get { self[ScreenToolbarItemsKey.self] }
        set { self[ScreenToolbarItemsKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {
    func screenTitle(_ title: String) -> some View {
        environment(\.screenTitle, title)
    }

    func screenEdgeInsets(_ insets: ScreenEdgeInsets) -> some View {
        environment(\.screenEdgeInsets, insets)
    }

    func screenBackground(_ type: ScreenBackgroundType) -> some View {
        environment(\.screenBackgroundType, type)
    }

    func screenNavigationBarHidden(_ hidden: Bool = true) -> some View {
        environment(\.screenNavigationBarHidden, hidden)
    }

    func screenBackButtonHidden(_ hidden: Bool = true) -> some View {
        environment(\.screenBackButtonHidden, hidden)
    }

    func screenIgnoresTopEdge(_ ignores: Bool = true) -> some View {
        environment(\.screenIgnoresTopEdge, ignores)
    }

    func screenToolbar(
        @CustomToolbarItemsBuilder items: () -> [CustomToolbarItem]
    ) -> some View {
        environment(\.screenToolbarItems, items())
    }
}
