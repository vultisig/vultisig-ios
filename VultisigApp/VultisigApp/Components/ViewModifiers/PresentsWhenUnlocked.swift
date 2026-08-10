//
//  PresentsWhenUnlocked.swift
//  VultisigApp
//

import SwiftUI

/// The rule behind ``SwiftUI/View/presentsWhenUnlocked(after:perform:)``, kept as
/// a value rather than living inside the view modifier so a test can drive it.
///
/// A **hold**, not a queue. Every caller is an idempotent "do I still owe the
/// user this sheet?" check, so a caller that asked three times while the gate was
/// up wants one answer once it comes down, not three.
struct AppLockPresentationHold {

    private(set) var isHolding = false

    /// A check has come due.
    /// - Returns: whether it may run now.
    mutating func requested(whileLocked isLocked: Bool) -> Bool {
        guard isLocked else {
            // Clearing here rather than only on the unlock is what stops the
            // check running twice. SwiftUI delivers the lock's `onChange` after
            // the flag has already changed, so a request landing in that window
            // runs immediately — and would then be run a second time by the
            // drain that is still on its way.
            isHolding = false
            return true
        }
        isHolding = true
        return false
    }

    /// The gate went up or came down.
    /// - Returns: whether a held check should run now.
    mutating func lockChanged(isLocked: Bool) -> Bool {
        guard !isLocked, isHolding else { return false }
        isHolding = false
        return true
    }
}

/// Nothing. The parameter exists so both `presentsWhenUnlocked` overloads share
/// one implementation; a value that can never differ from itself is a trigger
/// that never fires.
private struct NeverChanges: Equatable {}

private struct PresentsWhenUnlockedModifier<Trigger: Equatable>: ViewModifier {

    /// Read from the shared instance rather than from the environment, and it is
    /// not a shortcut. The document scene applies this modifier *outside* the
    /// view that installs the environment objects, and environment flows
    /// downward — an `@EnvironmentObject` there would find nothing and trap. The
    /// instance is the same one the environment carries: `VultisigApp` seeds its
    /// `@StateObject` from `AppViewModel.shared`.
    @ObservedObject private var appViewModel: AppViewModel = .shared

    let trigger: Trigger
    let delay: Duration
    let check: () -> Void

    @State private var hold = AppLockPresentationHold()

    func body(content: Content) -> some View {
        content
            .onLoad { request() }
            .onChange(of: trigger) { _, _ in request() }
            .onChange(of: appViewModel.isPasscodeLocked) { _, isLocked in
                guard hold.lockChanged(isLocked: isLocked) else { return }
                check()
            }
    }

    private func request() {
        guard delay > .zero else {
            runIfUnlocked()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            runIfUnlocked()
        }
    }

    private func runIfUnlocked() {
        guard hold.requested(whileLocked: appViewModel.isPasscodeLocked) else { return }
        check()
    }
}

private struct HoldsPresentationWhileLockedModifier: ViewModifier {

    /// See ``PresentsWhenUnlockedModifier``.
    @ObservedObject private var appViewModel: AppViewModel = .shared

    @Binding var isPresented: Bool

    @State private var hold = AppLockPresentationHold()

    func body(content: Content) -> some View {
        content
            .onLoad { holdIfLocked() }
            .onChange(of: isPresented) { _, _ in holdIfLocked() }
            .onChange(of: appViewModel.isPasscodeLocked) { _, isLocked in
                guard hold.lockChanged(isLocked: isLocked) else { return }
                isPresented = true
            }
    }

    private func holdIfLocked() {
        guard isPresented else { return }
        guard !hold.requested(whileLocked: appViewModel.isPasscodeLocked) else { return }
        isPresented = false
    }
}

extension View {

    /// Holds a presentation whose flag is raised from somewhere the view cannot
    /// gate — an in-flight lookup that completes after the app relocked, say —
    /// putting the flag back down while the gate is up and raising it again when
    /// the gate comes down.
    ///
    /// The closure-shaped overloads below cover a screen that asks *itself* a
    /// question on load, where holding the question is enough. This one covers
    /// the case where there is no question left to hold, only an answer that has
    /// already arrived.
    func presentsWhenUnlocked(_ isPresented: Binding<Bool>) -> some View {
        modifier(HoldsPresentationWhileLockedModifier(isPresented: isPresented))
    }

    /// Runs `check` once the view has loaded — but never while the passcode gate
    /// is up. A check that comes due behind the lock screen is held, and run the
    /// moment the gate comes down.
    ///
    /// The gate covers what the app *shows*. This covers what the app *raises*,
    /// which is a separate problem and the reason a lock screen is not enough on
    /// its own: several screens ask themselves on load whether they owe the user
    /// a sheet, and a sheet is presented in a layer the gate's overlay cannot
    /// reach. On a gated cold start those answers arrive half a second after the
    /// lock screen went up, and a fast-vault password prompt then sits above it
    /// taking input.
    ///
    /// - Parameters:
    ///   - delay: how long after load to ask. The delay runs whether or not the
    ///     app is locked; the lock is consulted when it expires.
    ///   - check: the question, asked in full each time — it is re-run on unlock
    ///     rather than replayed, so a condition that stopped being true in the
    ///     meantime raises nothing.
    func presentsWhenUnlocked(
        after delay: Duration = .zero,
        perform check: @escaping () -> Void
    ) -> some View {
        modifier(
            PresentsWhenUnlockedModifier(
                trigger: NeverChanges(),
                delay: delay,
                check: check
            )
        )
    }

    /// The same, asked again whenever `trigger` changes.
    func presentsWhenUnlocked<Trigger: Equatable>(
        on trigger: Trigger,
        after delay: Duration = .zero,
        perform check: @escaping () -> Void
    ) -> some View {
        modifier(
            PresentsWhenUnlockedModifier(
                trigger: trigger,
                delay: delay,
                check: check
            )
        )
    }
}
