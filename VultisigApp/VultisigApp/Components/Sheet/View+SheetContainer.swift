//
//  View+SheetContainer.swift
//  VultisigApp
//
//  Wraps sheet content with the platform-specific container the wallet
//  uses across pickers: a `NavigationStack` on iOS (so toolbars and
//  large-title navigation render) and the fitted sizing + animation
//  bypass on macOS.
//

import SwiftUI

private struct SheetContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        NavigationStack {
            content
        }
        #else
        content
            .presentationSizingFitted()
            .applySheetSize()
            .transaction { $0.disablesAnimations = true }
        #endif
    }
}

extension View {
    func sheetContainer() -> some View {
        modifier(SheetContainerModifier())
    }
}
