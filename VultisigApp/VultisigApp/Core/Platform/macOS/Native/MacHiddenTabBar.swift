//
//  MacHiddenTabBar.swift
//  VultisigApp
//

#if os(macOS)
import AppKit
import SwiftUI

/// Hides the native macOS tab strip while preserving SwiftUI's pages and selection.
struct MacHiddenTabBar: NSViewRepresentable {
    func makeNSView(context _: Context) -> TabBarHidingView {
        TabBarHidingView()
    }

    func updateNSView(_ nsView: TabBarHidingView, context _: Context) {
        nsView.hideNativeTabs()
    }

    final class TabBarHidingView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            hideNativeTabs()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideNativeTabs()
        }

        override func layout() {
            super.layout()
            hideNativeTabs()
        }

        func hideNativeTabs() {
            // A missing tab label no longer suppresses the native control on macOS.
            // Resolve only the tab view containing this page, never another tab view
            // in the window. SwiftUI may restore its style during a later update.
            var ancestor = superview
            while let view = ancestor {
                if let tabView = view as? NSTabView {
                    if tabView.tabViewType != .noTabsNoBorder {
                        tabView.tabViewType = .noTabsNoBorder
                    }
                    if tabView.drawsBackground {
                        tabView.drawsBackground = false
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
#endif
