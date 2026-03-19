//
//  NavigationStackVisibilityModifier.swift
//  VultisigApp
//
//  Created on 2026-02-17.
//

import SwiftUI

/// Tracks whether a view is the visible (top) view in a NavigationStack.
///
/// On macOS, `onAppear`/`onDisappear` don't fire when views are pushed/popped
/// on top of the current view. This modifier observes the router's navigation path
/// to reliably detect visibility changes on both platforms.
private struct NavigationStackVisibilityModifier: ViewModifier {
    let onChange: (Bool) -> Void

    @Environment(\.router) private var router
    @State private var viewDepth: Int?
    @State private var isCovered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if viewDepth == nil {
                    viewDepth = router.navPath.count
                    isCovered = false
                    onChange(true)
                }
            }
            .onDisappear {
                onChange(false)
                viewDepth = nil
                isCovered = false
            }
            .onReceive(router.$navPath) { newPath in
                guard let depth = viewDepth else { return }

                if newPath.count > depth && !isCovered {
                    isCovered = true
                    onChange(false)
                } else if newPath.count == depth && isCovered {
                    isCovered = false
                    onChange(true)
                }
            }
    }
}

extension View {
    /// Calls `action` with `true` when the view becomes the top of the navigation stack,
    /// and `false` when another view is pushed on top or the view disappears.
    func onNavigationStackChange(perform action: @escaping (_ isVisible: Bool) -> Void) -> some View {
        modifier(NavigationStackVisibilityModifier(onChange: action))
    }
}
