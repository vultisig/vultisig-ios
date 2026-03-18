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
                blurContent = newValue > 0
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
