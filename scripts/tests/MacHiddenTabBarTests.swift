// Run with scripts/test-macos-hidden-tab-bar.sh on macOS.
// These checks use the production adapter without loading the wallet or its data.
import AppKit
import SwiftUI

@main
@MainActor
struct MacHiddenTabBarTests {
    static var checks = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    static func main() {
        _ = NSApplication.shared
        let outer = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let inner = NSTabView(frame: outer.bounds)
        let first = NSTabViewItem(identifier: "wallet")
        first.view = NSView(frame: inner.bounds)
        let second = NSTabViewItem(identifier: "defi")
        second.view = NSView(frame: inner.bounds)
        inner.addTabViewItem(first)
        inner.addTabViewItem(second)
        inner.selectTabViewItem(second)
        let outerItem = NSTabViewItem(identifier: "outer")
        outerItem.view = inner
        outer.addTabViewItem(outerItem)
        let probe = MacHiddenTabBar.TabBarHidingView(frame: .zero)
        probe.hideNativeTabs()
        expect(probe.superview == nil, "unattached adapter is harmless")
        second.view!.addSubview(probe)
        expect(inner.tabViewType == .noTabsNoBorder, "attachment hides nearest native tabs")
        expect(outer.tabViewType == .topTabsBezelBorder, "outer tab view remains unchanged")
        expect(!inner.drawsBackground, "page background remains transparent")
        expect(inner.selectedTabViewItem === second, "selected page is preserved")
        expect(inner.tabViewItems.count == 2 && inner.tabViewItems[0] === first, "page identities are preserved")
        for _ in 0..<20 {
            inner.tabViewType = .topTabsBezelBorder
            probe.layout()
            expect(inner.tabViewType == .noTabsNoBorder, "layout restores hidden tabs after a style reset")
        }
        let other = NSTabView(frame: inner.frame)
        let otherItem = NSTabViewItem(identifier: "other")
        otherItem.view = NSView(frame: other.bounds)
        other.addTabViewItem(otherItem)
        probe.removeFromSuperview()
        otherItem.view!.addSubview(probe)
        expect(other.tabViewType == .noTabsNoBorder, "reparented adapter resolves its new tab view")
        expect(outer.tabViewType == .topTabsBezelBorder, "reparenting never changes unrelated tabs")
        expect(probe.hitTest(.zero) == nil, "adapter never intercepts mouse events")
        print("All \(checks) AppKit checks passed")
    }
}
