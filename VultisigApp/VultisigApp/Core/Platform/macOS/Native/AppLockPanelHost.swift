//
//  AppLockPanelHost.swift
//  VultisigApp
//

#if os(macOS)
import AppKit
import SwiftUI

/// A borderless window whose only job is to be above everything the app can
/// present.
///
/// `canBecomeKey` is overridden because a borderless window cannot become key by
/// default, and the Mac's passcode entry is typed on a hardware keyboard — a lock
/// screen nothing can be typed into is a lock screen with no way out of it.
final class AppLockPanel: NSWindow {

    let host: NSHostingController<AppLockHostedScreen>

    init(screen: AppLockHostedScreen) {
        self.host = NSHostingController(rootView: screen)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The panel is sized from the window it covers, never from its content —
        // left to itself a hosting controller resizes the window around its own
        // fitting size, and a lock screen that fits its keypad is a lock screen
        // with the wallet showing around it.
        host.sizingOptions = []
        contentViewController = host
        backgroundColor = NSColor(Theme.colors.bgPrimary)
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        // The level is **not** set here. It belongs to the app's activation state
        // and is owned by ``AppLockPanelHost/applyPanelLevel()`` — see there for
        // why it cannot simply be raised once and left.
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The Mac's half of ``AppLockHost``: a panel attached over each of the app's
/// windows, above everything that window can present — and never above another
/// application, which is what ``applyPanelLevel()`` is for.
///
/// Needed on every macOS version, not only where `CrossPlatformSheet` uses a
/// native sheet. Below macOS 26 that modifier does draw its sheets inside the
/// view hierarchy, where the root overlay already covers them — but every
/// `.alert` and every plain `.sheet` is a window-attached sheet whatever the
/// version, and no overlay reaches those.
@MainActor
final class AppLockPanelHost: ObservableObject {

    static let shared = AppLockPanelHost()

    /// See ``AppLockWindowHost/hostsLockScreen`` — same property, same reason for
    /// starting `true`.
    @Published private(set) var hostsLockScreen = true

    private var panels: [ObjectIdentifier: AppLockPanel] = [:]
    /// The window whose panel carries the keypad. Held so that clicking a covered
    /// window moves the keypad there rather than leaving it two windows away.
    private weak var interactiveWindow: NSWindow?
    private var current: AppLockPresentation = .uncovered
    private var callbacks: Callbacks?
    /// Invalidates the completion of a fade that a re-raise has overtaken, so a
    /// panel just put back up is not torn down underneath itself.
    private var lowerToken = 0
    /// Whether the app is frontmost. The only condition under which a panel may
    /// be elevated — see ``applyPanelLevel()``.
    private var isAppActive = NSApp.isActive

    private let lowerDuration: TimeInterval = 0.25

    private struct Callbacks {
        let onUnlocked: () -> Void
        let onAttemptFailed: () -> Void
    }

    init() {
        observeWindows()
    }

    func update(
        to presentation: AppLockPresentation,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void
    ) {
        guard presentation != .uncovered else {
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
        let hosts = coverableWindows

        guard !hosts.isEmpty else {
            if presentation.isGate {
                hostsLockScreen = false
            }
            return
        }

        // A window that has been closed or minimised since the last raise takes
        // its panel with it. Left behind, a hidden panel keeps a live lock screen
        // — and so a second biometric attempt and a second unlock state.
        discardPanelsNotCovering(hosts)

        // Overtakes any fade still running, so a panel put back up here is not
        // torn down by the completion of the lowering it interrupted.
        lowerToken += 1

        if presentation.isGate {
            hostsLockScreen = true
        }

        // One interactive lock screen, as on iOS: ``EnterPasscodeScreen`` starts a
        // biometric attempt from its `.task`, so one per window would be one Touch
        // ID prompt per window.
        let interactive = hosts.first { $0 === interactiveWindow }
            ?? hosts.first { $0.isMainWindow }
            ?? hosts.first
        interactiveWindow = interactive

        for window in hosts {
            show(
                window === interactive ? presentation : .cover,
                over: window,
                onUnlocked: onUnlocked,
                onAttemptFailed: onAttemptFailed
            )
        }

        applyPanelLevel()
        callbacks = Callbacks(onUnlocked: onUnlocked, onAttemptFailed: onAttemptFailed)
        current = presentation
    }

    /// Elevates the panels **only while the app is frontmost**.
    ///
    /// Both halves of that are load bearing, and the first version of this got the
    /// second half wrong badly enough to make the app unusable.
    ///
    /// **It has to be elevated at all**, because a child window does not beat an
    /// attached sheet. Measured, not assumed: a borderless child added with
    /// `ordered: .above` lands *below* the parent's attached sheet at `.normal`,
    /// whether it was attached before the sheet began or after — and above it at
    /// `.modalPanel`. Sheet coverage is the whole reason this panel exists, so
    /// plain child ordering does not do the job.
    ///
    /// **It has to stop being elevated when the app is not frontmost**, because
    /// levels on macOS are *global, not per-app*: anything above `.normal` floats
    /// over every other application. Raised unconditionally, the lock screen sat
    /// on top of Finder and everything else — and it did it exactly when the app
    /// went to the background, which is when the cover goes up. `hidesOnDeactivate`
    /// did not contain that and could not: the panel is ordered front *after* the
    /// app has deactivated, so the hide it was meant to trigger had already
    /// happened.
    ///
    /// While the app *is* frontmost, an elevated window of its own costs nothing —
    /// every other application is behind the active app regardless.
    private func applyPanelLevel() {
        let level: NSWindow.Level = isAppActive ? .modalPanel : .normal
        for panel in panels.values where panel.level != level {
            panel.level = level
        }
    }

    private func show(
        _ presentation: AppLockPresentation,
        over window: NSWindow,
        onUnlocked: @escaping () -> Void,
        onAttemptFailed: @escaping () -> Void
    ) {
        let key = ObjectIdentifier(window)
        let panel = panels[key] ?? AppLockPanel(
            screen: AppLockHostedScreen(presentation: .cover, onUnlocked: {}, onAttemptFailed: {})
        )
        panels[key] = panel

        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.setFrame(window.appLockCoverFrame, display: true)
        // A fade may still be running on this panel, and assigning `alphaValue`
        // outside an animation context would give that animation a new target
        // rather than stopping it — leaving the lock translucent over the wallet.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.ignoresMouseEvents = false
        panel.orderFront(nil)

        if presentation.isGate {
            panel.makeKey()
        }

        panel.host.rootView = AppLockHostedScreen(
            presentation: presentation,
            onUnlocked: onUnlocked,
            onAttemptFailed: onAttemptFailed
        )
    }

    /// The app's own top-level windows. Sheets are excluded because they are
    /// children of the window they belong to, and covering the parent covers them.
    private var coverableWindows: [NSWindow] {
        NSApp.windows.filter { window in
            !(window is AppLockPanel)
                && window.isVisible
                && !window.isSheet
                && window.parent == nil
                && window.canBecomeMain
        }
    }

    // MARK: - Lowering

    private func lower(animated: Bool) {
        guard !panels.isEmpty else { return }

        lowerToken += 1
        let token = lowerToken
        let lowering = panels

        // Key goes back to the window the keypad was covering — named, not
        // whichever entry the dictionary happens to yield last — and it goes back
        // before the fade, so the app is usable for the whole of it.
        let restored = lowering.values.first(where: \.isKeyWindow)?.parent
            ?? interactiveWindow
            ?? coverableWindows.first
        lowering.values.forEach { $0.ignoresMouseEvents = true }
        restored?.makeKey()
        interactiveWindow = nil

        guard animated else {
            panels = [:]
            lowering.values.forEach(dismantle)
            return
        }

        // The panels stay in `panels` until the fade finishes, so a gate raised
        // inside that quarter second reuses the one already there rather than
        // standing a second interactive lock screen up beside it.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = lowerDuration
            lowering.values.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self, token == self.lowerToken else { return }
            self.panels = [:]
            lowering.values.forEach(self.dismantle)
        })
    }

    private func dismantle(_ panel: AppLockPanel) {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func discardPanelsNotCovering(_ hosts: [NSWindow]) {
        let live = Set(hosts.map(ObjectIdentifier.init))
        for (key, panel) in panels where !live.contains(key) {
            panels.removeValue(forKey: key)
            dismantle(panel)
        }
    }

    // MARK: - Windows

    /// The host outlives every window the app can open, so these are never
    /// removed.
    ///
    /// The blocks run on `OperationQueue.main`, which is the main thread, so they
    /// step straight into the actor rather than hopping — a hop would leave the
    /// panels a runloop turn behind the windows they are covering.
    private func observeWindows() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self?.elect(window)
            }
        }

        // A passive panel can still become key, and the keypad is not in it. The
        // click that made it key is the user saying which window they want to
        // unlock from.
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let panel = notification.object as? AppLockPanel,
                      let parent = panel.parent else { return }
                self?.elect(parent)
            }
        }

        center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self?.discardPanel(for: ObjectIdentifier(window))
            }
        }

        // A child window follows its parent when the parent moves, but not when
        // it resizes — and a panel left at the old size is a lock screen with the
        // wallet showing down one edge.
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let window = notification.object as? NSWindow else { return }
                    self?.syncPanelFrame(over: window)
                }
            }
        }

        // The activation state is what decides whether the panels may be
        // elevated, so it is tracked rather than sampled: `NSApp.isActive` is
        // still `true` inside `willResignActive`, and that notification is the
        // very moment the privacy cover goes up.
        center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isAppActive = true
                self?.applyPanelLevel()
            }
        }

        center.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isAppActive = false
                self?.applyPanelLevel()
            }
        }
    }

    /// Hands the interactive lock screen to the window the user just moved to, so
    /// the keypad is in the one being looked at.
    ///
    /// A no-op when it is already there, which is what keeps the `makeKey` inside
    /// the re-raise from electing its way round in a circle.
    private func elect(_ window: NSWindow) {
        guard current.isGate, let callbacks, window !== interactiveWindow else { return }
        interactiveWindow = window
        raise(
            current,
            onUnlocked: callbacks.onUnlocked,
            onAttemptFailed: callbacks.onAttemptFailed
        )
    }

    private func syncPanelFrame(over window: NSWindow) {
        guard let panel = panels[ObjectIdentifier(window)] else { return }
        panel.setFrame(window.appLockCoverFrame, display: true)
    }

    private func discardPanel(for key: ObjectIdentifier) {
        guard let panel = panels.removeValue(forKey: key) else { return }
        dismantle(panel)
    }
}

private extension NSWindow {

    /// The part of a window the lock has to cover: everything the app draws, and
    /// nothing else.
    ///
    /// Not `frame`. Covering the title bar takes the traffic lights with it, and
    /// a lock screen behind which the window can be neither closed nor minimised
    /// is one there is no way out of short of force quitting.
    /// `contentLayoutRect` stops below the title bar, which shows a window title
    /// and nothing about a wallet.
    var appLockCoverFrame: NSRect {
        convertToScreen(contentLayoutRect)
    }
}
#endif
