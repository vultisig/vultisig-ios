//
//  AppLockWindowHost.swift
//  VultisigApp
//

#if os(iOS)
import SwiftUI
import UIKit

/// A window whose only job is to be above everything the app can present.
///
/// A subclass rather than a plain `UIWindow` for two reasons: it can be told
/// apart from the app's own — see ``UIApplication/activeContentWindow`` — and it
/// keeps a typed handle on its host so the screen inside can be swapped without
/// casting `rootViewController` back.
final class AppLockWindow: UIWindow {

    let host: UIHostingController<AppLockHostedScreen>

    init(scene: UIWindowScene, screen: AppLockHostedScreen) {
        self.host = UIHostingController(rootView: screen)
        super.init(windowScene: scene)
        host.view.backgroundColor = UIColor(Theme.colors.bgPrimary)
        rootViewController = host
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("AppLockWindow is only ever made in code")
    }
}

/// Puts the privacy cover and the lock screen in a window of their own, one per
/// scene, above the layer sheets and alerts are presented in.
///
/// Nothing is dismissed to achieve it. Window order is by level first, and a
/// presented sheet lives in the key window's hierarchy — so a window at a raised
/// level simply covers it, and the user's sheet is still there after unlocking.
@MainActor
final class AppLockWindowHost: ObservableObject {

    static let shared = AppLockWindowHost()

    /// Whether the raised window is the thing carrying the lock screen, so the
    /// root overlay knows to draw an opaque floor rather than a second copy of
    /// it.
    ///
    /// It starts `true` — **assumed, not observed**, and that is the only
    /// ordering that works. A raise happens on the view's first appearance, one
    /// step after its first body; starting `false` would have the overlay mount
    /// an interactive lock screen for that step, and that screen starts a
    /// biometric attempt from its `.task`. Two live copies is two Face ID prompts
    /// racing on every gated cold start. So the window is assumed to work and
    /// corrected when a raise actually fails, rather than the other way round.
    @Published private(set) var hostsLockScreen = true

    private var windows: [ObjectIdentifier: AppLockWindow] = [:]
    /// What was key in each scene before the gate took it, so unlocking gives it
    /// back. Per scene, because key windows are.
    private var previousKeyWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var current: AppLockPresentation = .uncovered
    private var callbacks: Callbacks?
    /// Invalidates the completion of a fade that a re-raise has overtaken, so a
    /// window just put back up is not dismantled underneath itself.
    private var lowerToken = 0

    private let lowerDuration: TimeInterval = 0.25

    private struct Callbacks {
        let onUnlocked: () -> Void
        let onAttemptFailed: () -> Void
    }

    private final class WeakWindow {
        weak var window: UIWindow?
        init(_ window: UIWindow?) { self.window = window }
    }

    init() {
        observeScenes()
    }

    func update(
        to presentation: AppLockPresentation,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void
    ) {
        guard presentation != .uncovered else {
            // Asymmetric, and the insertion side is the point: a lock that fades
            // in is a lock you can see through while it arrives. Going up is
            // instant; coming down fades, because by then the app is unlocked and
            // there is nothing left to hide. The privacy cover never faded and
            // still does not, so only a gate animates away.
            lower(animated: current.isGate)
            current = .uncovered
            callbacks = nil
            return
        }

        raise(presentation, onUnlocked: onUnlocked, onAttemptFailed: onAttemptFailed)
    }

    // MARK: - Raising

    private func raise(
        _ presentation: AppLockPresentation,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void
    ) {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState != .unattached }

        guard !scenes.isEmpty else {
            // No scene, so no window is possible — a `UIWindow` needs one, and
            // the gate is decided in `VultisigApp.init()`, before any exists. The
            // root overlay carries the lock screen itself, which is what it is
            // there for.
            if presentation.isGate {
                hostsLockScreen = false
            }
            return
        }

        // Overtakes any fade still running, so a window put back up here is not
        // torn down by the completion of the lowering it interrupted.
        lowerToken += 1

        if presentation.isGate {
            // The keyboard is in a window of its own, far above `.alert`, so a
            // field that was first responder under a sheet would go on drawing
            // its keyboard over the lock screen.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
            // Published before the screen below is mounted, so the overlay's copy
            // is already on its way out rather than being taken down after a
            // second one has appeared.
            hostsLockScreen = true
        }

        // Exactly one scene gets the interactive lock screen. `EnterPasscodeScreen`
        // starts a biometric attempt from its `.task`, so one per scene would be
        // one Face ID prompt per scene; the others are covered instead, and the
        // election is redone whenever a different scene activates.
        let interactiveScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first

        for scene in scenes {
            show(
                scene === interactiveScene ? presentation : .cover,
                in: scene,
                onUnlocked: onUnlocked,
                onAttemptFailed: onAttemptFailed
            )
        }

        callbacks = Callbacks(onUnlocked: onUnlocked, onAttemptFailed: onAttemptFailed)
        current = presentation
    }

    /// Makes the window for `scene` visible — and key, for a gate — **before**
    /// mounting the real screen into it.
    ///
    /// The order matters: ``EnterPasscodeScreen`` starts a biometric attempt from
    /// its `.task`, so building it into a window that is not on screen yet races
    /// the Face ID prompt against the window the prompt is supposed to appear
    /// over. A new window opens on the brand screen instead, which is exactly
    /// what the lock screen itself draws while that attempt runs, so there is no
    /// seam between the two.
    private func show(
        _ presentation: AppLockPresentation,
        in scene: UIWindowScene,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void
    ) {
        let key = ObjectIdentifier(scene)
        let window = windows[key] ?? makeWindow(for: scene)
        windows[key] = window

        if presentation.isGate,
           previousKeyWindows[key] == nil,
           let previous = scene.keyWindow,
           !(previous is AppLockWindow) {
            previousKeyWindows[key] = WeakWindow(previous)
        }

        // A fade may still be running on this window, and the value it left
        // behind is what `alpha` would otherwise keep.
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.isUserInteractionEnabled = true

        if presentation.isGate {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = false
        }

        window.host.rootView = AppLockHostedScreen(
            presentation: presentation,
            onUnlocked: onUnlocked,
            onAttemptFailed: onAttemptFailed
        )
    }

    private func makeWindow(for scene: UIWindowScene) -> AppLockWindow {
        let window = AppLockWindow(
            scene: scene,
            screen: AppLockHostedScreen(presentation: .cover, onUnlocked: {}, onAttemptFailed: {})
        )
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = UIColor(Theme.colors.bgPrimary)
        return window
    }

    // MARK: - Lowering

    private func lower(animated: Bool) {
        guard !windows.isEmpty else { return }

        lowerToken += 1
        let token = lowerToken
        let lowering = windows

        for (key, window) in lowering {
            window.isUserInteractionEnabled = false
            // Key goes back first, so the app underneath is usable for the whole
            // of the fade rather than only once it has finished.
            previousKeyWindows[key]?.window?.makeKey()
        }
        previousKeyWindows = [:]

        guard animated else {
            windows = [:]
            lowering.values.forEach(dismantle)
            return
        }

        // The windows stay in `windows` until the fade finishes, so a gate raised
        // inside that quarter second reuses the one already there rather than
        // standing a second interactive lock screen up beside it.
        UIView.animate(
            withDuration: lowerDuration,
            animations: { lowering.values.forEach { $0.alpha = 0 } },
            completion: { [weak self] _ in
                guard let self, token == self.lowerToken else { return }
                self.windows = [:]
                lowering.values.forEach(self.dismantle)
            }
        )
    }

    private func dismantle(_ window: AppLockWindow) {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }

    // MARK: - Scenes

    /// The host outlives every scene the app can open, so these are never
    /// removed.
    private func observeScenes() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reelectInteractiveScene() }
        }

        center.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            let key = ObjectIdentifier(scene)
            Task { @MainActor in self?.discardWindow(for: key) }
        }
    }

    /// Hands the interactive lock screen to whichever scene the user just moved
    /// to. Without it the scene that happened to be active when the gate went up
    /// keeps the keypad, and every other one is left with a screen that cannot be
    /// typed into.
    private func reelectInteractiveScene() {
        guard current.isGate, let callbacks else { return }
        raise(
            current,
            onUnlocked: callbacks.onUnlocked,
            onAttemptFailed: callbacks.onAttemptFailed
        )
    }

    private func discardWindow(for key: ObjectIdentifier) {
        previousKeyWindows[key] = nil
        guard let window = windows.removeValue(forKey: key) else { return }
        dismantle(window)
    }
}
#endif
