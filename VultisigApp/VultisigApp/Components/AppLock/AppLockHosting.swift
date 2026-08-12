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
    /// The store holds sealed key shares and the key that opens them is
    /// confirmed gone, so nothing on this device can read them.
    ///
    /// It is here rather than in the app's own hierarchy for the reason the
    /// gate is: the wallet underneath renders names, addresses and balances
    /// perfectly well and only fails at signing, so anything short of covering
    /// it — sheets and full-screen covers included — is the silent open this
    /// state exists to stop.
    ///
    /// No generation, because there is nothing to re-raise it over: it is
    /// derived once at launch and stands until the user leaves it for the
    /// import flow.
    case recovery

    /// Whether this presentation carries a screen the user acts on.
    ///
    /// The distinction the hosts need, and it is not "is it the gate": an
    /// interactive screen has to be in the key window to receive input, exactly
    /// one scene may hold it, and the root overlay must not draw a second live
    /// copy of it. The gate and the recovery screen both want all three.
    var isInteractive: Bool {
        switch self {
        case .gate, .recovery:
            return true
        case .uncovered, .cover:
            return false
        }
    }

    /// Kept apart from ``isInteractive`` because only the gate may fade away.
    ///
    /// The gate fades because by then the app is unlocked and there is nothing
    /// left to hide. The recovery screen comes down onto a screen the app has
    /// *just pushed underneath it*, and a quarter second of translucency there
    /// is a quarter second of the wallet showing through on the way to the
    /// import flow. It goes at once instead.
    var isGate: Bool {
        if case .gate = self { return true }
        return false
    }
}

/// What the raised window draws.
///
/// Every state in one root rather than a window each: see ``AppLockPresentation``
/// for why they must not be able to disagree.
struct AppLockHostedScreen: View {

    let presentation: AppLockPresentation
    /// A picture of the app taken as it left, blurred, for the privacy cover to
    /// show — see ``PrivacyBackdrop``.
    ///
    /// Carried alongside the presentation rather than inside it, because it is
    /// not part of the decision: ``AppLockPresentation`` is what the app has
    /// concluded about itself and is compared for equality on every change,
    /// whereas this is one host's material for drawing one of those cases. The
    /// root overlay has no capture to offer and passes nothing, which is exactly
    /// the case ``CoverView`` falls back for.
    var backdrop: Image?
    let onUnlocked: () -> Void
    let onAttemptFailed: () -> Void
    /// Hands the user to the app's import flow from the recovery screen. The
    /// window is outside the app's navigation, so the route is a closure the
    /// app supplies rather than something this view can reach.
    let onRestoreFromBackup: () -> Void

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
            CoverView(backdrop: backdrop)
        case .gate(let generation):
            EnterPasscodeScreen(
                onUnlocked: onUnlocked,
                onAttemptFailed: onAttemptFailed
            )
            // A raise is a new screen, never a reused one. See
            // ``AppViewModel/passcodeGateGeneration``.
            .id(generation)
        case .recovery:
            KeyshareRecoveryScreen(onRestoreFromBackup: onRestoreFromBackup)
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
    let onRestoreFromBackup: () -> Void

    func body(content: Content) -> some View {
        content
            .onLoad { sync() }
            .onChange(of: presentation) { _, _ in sync() }
    }

    private func sync() {
        AppLockHost.shared.update(
            to: presentation,
            onUnlocked: onUnlocked,
            onAttemptFailed: onAttemptFailed,
            onRestoreFromBackup: onRestoreFromBackup
        )
    }
}

extension View {

    /// Hosts the privacy cover, the lock screen and the key-share recovery
    /// screen in a window above the app's own, so that a sheet, a full-screen
    /// cover or an alert already on screen is covered rather than left drawn on
    /// top.
    ///
    /// A sheet is presented in a layer a SwiftUI `.overlay` does not reach, which
    /// is why the root overlay alone was never enough. Window order is by level
    /// first and presented sheets live in the key window's hierarchy, so a window
    /// at a raised level covers them **without dismissing anything** — the user's
    /// sheet is still there after unlocking.
    func hostsAppLock(
        _ presentation: AppLockPresentation,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void,
        onRestoreFromBackup: @escaping () -> Void
    ) -> some View {
        modifier(
            HostsAppLockModifier(
                presentation: presentation,
                onUnlocked: onUnlocked,
                onAttemptFailed: onAttemptFailed,
                onRestoreFromBackup: onRestoreFromBackup
            )
        )
    }
}
