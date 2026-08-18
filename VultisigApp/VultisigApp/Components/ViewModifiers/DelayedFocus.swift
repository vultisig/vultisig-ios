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
        modifier(DelayedFocus(intent: intent, focus: focus, delay: delay))
    }
}

/// Applies `intent` to `focus` after `delay`, cancelling any application still
/// pending from an earlier change.
///
/// The cancellation is the point. An uncancelled `asyncAfter` lands whatever the
/// intent was when it was scheduled, so a screen that clears focus on its way to
/// another one can have the field handed back to it by a timer armed half a
/// second earlier — focus restored on a screen that has already left, and a
/// keyboard over the screen that replaced it. Same cancellable shape the staking
/// screen already uses for its own copy of this.
private struct DelayedFocus<Value: Hashable>: ViewModifier {
    let intent: Value
    let focus: FocusState<Value>.Binding
    let delay: TimeInterval

    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: intent) { _, newValue in
                task?.cancel()
                task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    focus.wrappedValue = newValue
                }
            }
            .onDisappear { task?.cancel() }
    }
}
