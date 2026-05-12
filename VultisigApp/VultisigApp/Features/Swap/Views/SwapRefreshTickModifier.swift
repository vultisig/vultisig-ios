//
//  SwapRefreshTickModifier.swift
//  VultisigApp
//
//  Shared 1-second tick used by SwapDetailsScreen and SwapVerifyScreen for
//  their quote-refresh countdowns. Both screens previously declared their own
//  `Timer.publish` + `onReceive` boilerplate; this modifier centralises it.
//

import SwiftUI

struct SwapRefreshTickModifier: ViewModifier {
    let onTick: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content.onReceive(timer) { _ in onTick() }
    }
}

extension View {
    /// Calls `onTick` once per second on the main run loop. Use for the swap
    /// quote-refresh countdown surfaced via `SwapRefreshQuoteCounter`.
    func swapRefreshTick(_ onTick: @escaping () -> Void) -> some View {
        modifier(SwapRefreshTickModifier(onTick: onTick))
    }
}
