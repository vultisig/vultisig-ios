//
//  DelayedFocus.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/06/2026.
//

import SwiftUI

public extension View {
    /// Bridges a plain "intended focus" state to a `@FocusState` by re-applying it after a short delay.
    ///
    /// SwiftUI drops focus changes that happen during the same view update or a
    /// sheet/navigation transition, so several screens express the desired focus through a
    /// plain `@State` "intent" value and then push it into the real `@FocusState` on a later
    /// runloop. This collapses the copy-pasted
    /// `onChange(of:) { asyncAfter { focusedField = newValue } }` idiom into one place.
    ///
    /// - Parameters:
    ///   - intent: the plain state value that expresses the desired focus.
    ///   - focus: the `@FocusState` binding to drive.
    ///   - delay: how long to wait before applying the focus. Defaults to `0.5`s — the value
    ///     every existing call site used.
    func delayedFocus<Value: Hashable>(
        from intent: Value,
        to focus: FocusState<Value>.Binding,
        delay: TimeInterval = 0.5
    ) -> some View {
        onChange(of: intent) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                focus.wrappedValue = newValue
            }
        }
    }
}
