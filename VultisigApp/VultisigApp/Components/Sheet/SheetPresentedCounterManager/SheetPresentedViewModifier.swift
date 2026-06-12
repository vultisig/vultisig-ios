//
//  SheetPresentedViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/10/2025.
//

import SwiftUI

extension View {
    /// Blurs navigation stack when `.platformSheet` gets presented
    func sheetPresentedStyle() -> some View {
        modifier(SheetPresentedViewModifier())
    }
}

private struct SheetPresentedViewModifier: ViewModifier {
    @Environment(\.sheetPresentedCounterManager) var sheetPresentedCounterManager

    @State var blurContent: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(blurContent ? overlayView : nil)
            .blur(radius: blurContent ? 6 : 0)
            .animation(.easeInOut(duration: 0.1), value: blurContent)
            .onReceive(sheetPresentedCounterManager.$counter) { newValue in
                // Guard the write so an unchanged value never emits a graph
                // mutation. The publisher lands on the runloop and can fire
                // during a sheet's own animated transition commit; a no-op
                // assignment mid-commit re-invalidates the laying-out root and
                // triggers a reentrant AppKit constraint update that crashes on
                // macOS. The counter changes more often than the boolean (every
                // increment/decrement), so this guard collapses most ticks to
                // no-ops.
                let shouldBlur = newValue > 0
                guard blurContent != shouldBlur else { return }
                blurContent = shouldBlur
            }
            #if os(iOS)
            // Remove blur when enter background as the iOS dismisses sheet
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                sheetPresentedCounterManager.resetCounter()
            }
            #endif
    }

    var overlayView: some View {
        Color.black
            .opacity(0.4)
            .ignoresSafeArea()
    }
}
