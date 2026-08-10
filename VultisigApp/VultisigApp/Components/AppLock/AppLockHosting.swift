//
//  AppLockHosting.swift
//  VultisigApp
//

import SwiftUI

/// What the app is covering itself with, as one value.
///
/// One value rather than two flags, because the ordering between them is load
/// bearing: `AppViewModel.enableAuth` raises the lock *before* it drops the
/// privacy cover, precisely so the home screen is never uncovered for the frames
/// a lock screen takes to mount. Deriving a single case from both keeps that one
/// decision instead of two racing ones.
enum AppLockPresentation: Equatable {
    /// The app is showing itself.
    case uncovered
    /// The logo, while the app is leaving, away, or coming back.
    case cover
    /// The lock screen. The generation is the lock screen's identity — see
    /// ``AppViewModel/passcodeGateGeneration``.
    case gate(generation: Int)

    var isGate: Bool {
        if case .gate = self { return true }
        return false
    }
}

/// What the raised window draws.
///
/// Two states in one root rather than a window each: see ``AppLockPresentation``
/// for why the two must not be able to disagree.
struct AppLockHostedScreen: View {

    let presentation: AppLockPresentation
    let onUnlocked: () -> Void
    let onAttemptFailed: () -> Void

    var body: some View {
        content
            // The window is outside the app's view hierarchy, so it inherits
            // none of the environment `ContentView` sets. These two are the ones
            // the lock screen's appearance depends on.
            .colorScheme(.dark)
            .accentColor(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .uncovered, .cover:
            CoverView()
        case .gate(let generation):
            EnterPasscodeScreen(
                onUnlocked: onUnlocked,
                onAttemptFailed: onAttemptFailed
            )
            // A raise is a new screen, never a reused one. See
            // ``AppViewModel/passcodeGateGeneration``.
            .id(generation)
        }
    }
}

/// The platform's implementation of "put this above everything the app can
/// present". `UIWindow` on iOS, `NSWindow` on the Mac.
#if os(iOS)
typealias AppLockHost = AppLockWindowHost
#elseif os(macOS)
typealias AppLockHost = AppLockPanelHost
#endif

private struct HostsAppLockModifier: ViewModifier {

    let presentation: AppLockPresentation
    let onUnlocked: () -> Void
    let onAttemptFailed: () -> Void

    func body(content: Content) -> some View {
        content
            .onLoad { sync() }
            .onChange(of: presentation) { _, _ in sync() }
    }

    private func sync() {
        AppLockHost.shared.update(
            to: presentation,
            onUnlocked: onUnlocked,
            onAttemptFailed: onAttemptFailed
        )
    }
}

extension View {

    /// Hosts the privacy cover and the lock screen in a window above the app's
    /// own, so that a sheet, a full-screen cover or an alert already on screen is
    /// covered rather than left drawn on top.
    ///
    /// A sheet is presented in a layer a SwiftUI `.overlay` does not reach, which
    /// is why the root overlay alone was never enough. Window order is by level
    /// first and presented sheets live in the key window's hierarchy, so a window
    /// at a raised level covers them **without dismissing anything** — the user's
    /// sheet is still there after unlocking.
    func hostsAppLock(
        _ presentation: AppLockPresentation,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void
    ) -> some View {
        modifier(
            HostsAppLockModifier(
                presentation: presentation,
                onUnlocked: onUnlocked,
                onAttemptFailed: onAttemptFailed
            )
        )
    }
}
