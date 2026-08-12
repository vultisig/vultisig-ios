//
//  AppViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import LocalAuthentication

class AppViewModel: ObservableObject {
    @AppStorage("showOnboarding") var showOnboarding: Bool = true
    @AppStorage("showCover") private var storedShowCover: Bool = true
    @AppStorage("isAuthenticationEnabled") var isAuthenticationEnabled: Bool = true
    @AppStorage("didAskForAuthentication") var didAskForAuthentication: Bool = false
    @AppStorage("lastRecordedTime") var lastRecordedTime: String = ""
    @AppStorage("vaultName") var vaultName: String = ""
    @AppStorage("selectedPubKeyECDSA") var selectedPubKeyECDSA: String = ""

    /// Whether the privacy cover is up.
    ///
    /// Written through rather than left as bare `@AppStorage`, because
    /// `@AppStorage` is a `DynamicProperty`: it publishes from a *view*, and from
    /// inside an `ObservableObject` it writes `UserDefaults` and tells nobody.
    /// The overlay got away with that by accident — every writer runs off a
    /// scene-phase change, which re-evaluates the app's body and re-reads the
    /// value on the way past. Anything that is not a view has no such accident to
    /// lean on, and a cover raised without being observed is a cover nothing
    /// takes down.
    var showCover: Bool {
        get { storedShowCover }
        set {
            guard newValue != storedShowCover else { return }
            objectWillChange.send()
            storedShowCover = newValue
        }
    }

    @Published var isAuthenticated = false
    /// Whether the passcode lock screen should be covering the app.
    @Published var isPasscodeLocked = false
    /// Whether this device holds sealed key shares with no key left to open
    /// them, so the recovery screen has to cover the app.
    ///
    /// Derived at launch from ``KeyshareInstallReconciler``'s outcome and not
    /// from the lock mode: anyone who has already hit this has `.deviceAuth`
    /// persisted, because reconciliation wrote it on their first launch.
    ///
    /// It is not re-derived while the app is running. The state cannot appear
    /// mid-session — the key does not go missing while the app is open — and
    /// the one way out of it, importing the `.vult`, is a screen in the app
    /// that this would be covering.
    @Published private(set) var isKeyshareRecoveryRequired = false
    /// Set for exactly as long as it takes ``ContentView`` to route to the
    /// import flow, then consumed.
    ///
    /// A trigger rather than a destination, and consumed rather than merely
    /// read, because every mounted scene sees it: two scenes acting on one tap
    /// would push the import route twice.
    @Published private(set) var isKeyshareRecoveryImportPending = false

    /// Whether anything the app raises over itself is currently up.
    ///
    /// The question every *other* part of the app is really asking when it looks
    /// at ``isPasscodeLocked``: may I present, navigate, or draw a banner right
    /// now? Both covers answer no, and for the same reason — a deeplink acted on
    /// behind one navigates and presents where nobody can see it, a foreground
    /// push banner is drawn by the system above every window the app owns, and a
    /// sheet raised behind one is a sheet the user finds instead of the screen
    /// they were sent to.
    ///
    /// Computed rather than stored, so it cannot go stale: both halves are
    /// `@Published`, so anything observing this object re-reads it when either
    /// moves.
    var isCoveredByAppLock: Bool {
        isPasscodeLocked || isKeyshareRecoveryRequired
    }
    /// Bumped every time the gate goes up, and used as the lock screen's
    /// identity so each raise gets a brand new one.
    ///
    /// Without it the lock screen is only *usually* new. A gate raised again
    /// while the previous one is still fading out is a re-insertion of a view
    /// SwiftUI may still be holding, and it comes back with the finished flag
    /// from the unlock that was dismissing it — so the next successful entry
    /// sets `didFinish` from `true` to `true`, `onChange` never fires, and a
    /// perfectly good passcode stops taking the screen down. A force quit is
    /// the only way out of that, which is the worst failure this screen has.
    /// Identity is what makes "new gate, new screen" true rather than likely,
    /// and it clears the stale entry text and error message with it.
    @Published private(set) var passcodeGateGeneration = 0
    @Published var showSplashView = true
    @Published var didUserCancelAuthentication = false
    @Published var canLogin = true
    @Published var authenticationType: AuthenticationType = .None

    // Properties to manage global navigation
    @Published private(set) var selectedVault: Vault?
    @Published private(set) var showingVaultSelector: Bool = false
    @Published var restartNavigation: Bool = false
    @Published var showCamera: Bool = false

    private let logic = AccountLogic()
    private let lockService: AppLockService
    /// Held rather than reached through `PasscodeService.shared`, so a test can
    /// drive a real service over a mock Keychain and watch the overlay follow
    /// it. Only its `nonisolated` members are used here, so no `await` — and
    /// that matters: an `await` would be a suspension point between asking
    /// whether a gate is required and acting on the answer.
    private let passcodeService: PasscodeService
    /// Injected rather than called directly so a test can prove it runs *before*
    /// the launch gate reads the lock mode, which is the whole property.
    private let reconcileInstall: @MainActor () -> KeyshareInstallReconciler.Outcome
    private var didTriggerAuthThisSession = false
    /// Whether the app has actually been to the background since the last time
    /// it came forward.
    ///
    /// The auto-lock interval is a rule about time spent *away*, but the hook
    /// that enforced it ran on every activation — and plenty of activations are
    /// not returns from anywhere. A Face ID sheet, Control Centre, an incoming
    /// call and a permission alert all make the app `.inactive` and then
    /// `.active` again without it ever leaving.
    ///
    /// That is what produced the Face ID loop: the sheet the lock screen itself
    /// raised counted as a foreground, `immediate` answered "relock, yes", and
    /// the gate went back up over the unlock that had just succeeded — which
    /// rebuilt the lock screen, which raised the sheet again. Requiring a real
    /// backgrounding is the fix for the whole family, not just the one case.
    private var didBackgroundSinceForeground = false
    /// Whether the return currently under way has already been evaluated.
    ///
    /// A return crosses two phases — `.inactive` as the zoom begins, `.active`
    /// when it ends — and ``enableAuth()`` is answered at the first of them.
    /// Letting the second run it again would not be a harmless repeat: the first
    /// consumes ``didBackgroundSinceForeground``, so the second reads the lock
    /// state afresh but can no longer act on most of what it finds. A
    /// `disablePasscode` completing in the third of a second between them would
    /// be read as "no gate required", lower the gate the first call raised, and
    /// then skip the device-auth fallback that is supposed to replace it —
    /// leaving the app open behind neither.
    ///
    /// One foreground, one decision, every branch acting on that one answer. It
    /// is the same rule ``enableAuth()`` keeps internally, extended to the pair
    /// of phases the decision now spans.
    private var didEvaluateForeground = false

    init(
        lockService: AppLockService = .shared,
        passcodeService: PasscodeService = .shared,
        reconcileInstall: @escaping @MainActor () -> KeyshareInstallReconciler.Outcome = {
            KeyshareInstallReconciler().reconcile()
        }
    ) {
        self.lockService = lockService
        self.passcodeService = passcodeService
        self.reconcileInstall = reconcileInstall
    }

    static let shared = AppViewModel()

    func restart() {
        set(selectedVault: selectedVault, restartNavigation: true)
    }

    func set(selectedVault: Vault?, showingVaultSelector: Bool = false, restartNavigation: Bool = true) {
        self.selectedVault = selectedVault
        self.vaultName = selectedVault?.name ?? ""
        self.selectedPubKeyECDSA = selectedVault?.pubKeyECDSA ?? ""

        self.showingVaultSelector = showingVaultSelector
        self.restartNavigation = restartNavigation

        if let vault = selectedVault {
            Task { await FastVaultEligibilityRefresher.shared.refreshIfStale(vault) }
        }
    }

    /// Triggers a fast-vault eligibility refresh for the currently selected vault
    /// if its cache is stale. Called by the app's scenePhase `.active` hook so
    /// the cache stays fresh after the app moves to the foreground.
    func refreshFastVaultEligibilityIfNeeded() {
        guard let vault = selectedVault else { return }
        Task { await FastVaultEligibilityRefresher.shared.refreshIfStale(vault) }
    }

    func loadSelectedVault(for vaults: [Vault]) {
        if vaultName.isEmpty || selectedPubKeyECDSA.isEmpty {
            // when vaultName is empty / selectedPubKeyECDSA is empty, select the first vault if available
            // otherwise the app have nothing to show
            set(selectedVault: vaults.first, showingVaultSelector: true)
            return
        }

        for vault in vaults {
            if vaultName == vault.name && selectedPubKeyECDSA == vault.pubKeyECDSA {
                set(selectedVault: vault)
                return
            }
        }

        set(selectedVault: nil, showingVaultSelector: true)
    }

    func authenticateUser() {
        didTriggerAuthThisSession = true

        #if DEBUG
        if CommandLine.arguments.contains("-skipAuthentication") {
            isAuthenticated = true
            isAuthenticationEnabled = true
            showSplashView = false
            didUserCancelAuthentication = false
            didAskForAuthentication = true
            return
        }
        #endif

        // The passcode gate is this install's lock, and the launch decision has
        // already been made — in the app's initializer, before any view existed.
        // Everything below is the legacy device-auth gate, and running it here
        // would put a system Face ID sheet in front of the lock screen for a
        // user who has already chosen a different lock.
        //
        // The splash comes down rather than staying up: the lock screen is an
        // overlay above everything, so it is already covering the app, and
        // leaving the splash underneath would strand the launch there once the
        // passcode is accepted — `onAppear` does not fire twice.
        //
        // Read off the flag, not off the predicate. `enableAuth()` derives the
        // predicate itself because it is the first thing to run after a
        // foreground and nothing has decided yet; here something has, and asking
        // again would be a second read that a transition on `PasscodeService`'s
        // executor could answer differently — the two disagreeing is how the app
        // ends up open behind no gate at all.
        //
        // The recovery screen counts the same way. It covers the app for the
        // same reason and is dismissed by no authentication of any kind, so a
        // system Face ID sheet in front of it would be a prompt with nothing
        // behind it.
        guard !isPasscodeLocked, !isKeyshareRecoveryRequired else {
            showSplashView = false
            didUserCancelAuthentication = false
            return
        }

        let context = LAContext()
        var error: NSError?

        getBiometricType()

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            authenticate(context)
        } else {
            isAuthenticationEnabled = false
            isAuthenticated = false
            showSplashView = false
            didUserCancelAuthentication = false
            didAskForAuthentication = true
        }
    }

    func authenticateUserIfNeeded() {
        guard !didAskForAuthentication else { return }
        authenticateUser()
    }

    private func authenticate(_ context: LAContext) {
        self.didAskForAuthentication = true
        if (context.biometryType == .faceID || context.biometryType == .touchID || context.biometryType == .opticID) && logic.isRunningOnPhysicalDevice() {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to check Face ID") { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.isAuthenticated = true
                        self.showSplashView = false
                        self.isAuthenticationEnabled = true
                        self.didUserCancelAuthentication = false
                    } else {
                        if let error = error as? LAError {
                            switch error.code {
                            case .biometryLockout, .biometryNotEnrolled, .biometryNotAvailable:
                                self.isAuthenticationEnabled = false
                                self.showSplashView = false
                            default:
                                self.isAuthenticationEnabled = true
                                self.showSplashView = true
                            }
                        }
                        self.isAuthenticated = false
                        self.didUserCancelAuthentication = true
                    }
                }
            }
        } else {
            isAuthenticationEnabled = false
            isAuthenticated = false
            showSplashView = false
            didUserCancelAuthentication = false
        }
    }

    func revokeAuth() {
        showCover = true
        didTriggerAuthThisSession = false
        didBackgroundSinceForeground = true
        // A return that began and then turned back — the app was tapped and put
        // down again before it finished arriving — is a foreground that never
        // happened. The next one is entitled to its own decision.
        didEvaluateForeground = false
        lockService.noteBackgrounded()
    }

    /// Puts the logo over the app without touching any lock bookkeeping.
    ///
    /// `.inactive` is not `.background`, and the difference matters in both
    /// directions. It is the phase the system takes its app-switcher snapshot
    /// in, so a cover raised only at `.background` is raised *after* the picture
    /// of the balances has already been taken — and it is also what fires for a
    /// Control Centre pull or an incoming call, where the app has not gone
    /// anywhere.
    ///
    /// So: cover, yes — that is exactly what those moments need. Timestamp, no.
    /// `noteBackgrounded()` starts the auto-lock clock, and starting it because
    /// somebody glanced at Control Centre would re-lock people who never left
    /// the app.
    func coverForPrivacy() {
        showCover = true
    }

    /// Routes the one phase that means two opposite things.
    ///
    /// `.inactive` is the app leaving *and* the app coming back. It is what the
    /// system reports as the app-switcher snapshot is taken, and it is also what
    /// it reports the instant a return begins — a good third of a second before
    /// `.active` arrives at the end of the zoom. Nothing in the phase itself
    /// tells the two apart; only where it came from does.
    ///
    /// Both used to cover, and the return is why the app came forward oddly: the
    /// cover stayed up for the whole of the zoom and the wallet replaced it in a
    /// jump at the end, having been absent from the transition it was the
    /// destination of. Handing the return to ``enableAuth()`` here instead means
    /// the animation shows what the user is coming back to — the wallet, or the
    /// lock screen when the interval says it is time for one, since that is the
    /// same call that decides it and it raises the gate before it drops the
    /// cover. Nothing about the departure changes: the picture the app switcher
    /// keeps is still taken over the logo.
    /// What is given up for it is a window the width of an abandoned launch: the
    /// app is uncovered from here, so tapping the icon and putting the phone down
    /// again before the zoom finishes renders the wallet for those frames. The
    /// app reaches `.background` on that path like any other departure, and
    /// `revokeAuth()` covers it there — which is before the snapshot that
    /// actually outlives the moment is taken. What is bought with it is every
    /// ordinary return, of which there are thousands.
    func sceneBecameInactive(comingFrom previousPhase: ScenePhase) {
        guard previousPhase == .background else {
            coverForPrivacy()
            return
        }
        didEvaluateForeground = true
        enableAuth()
    }

    /// The end of the return, and by then usually nothing is left to do.
    ///
    /// `.active` is the only foreground signal an activation that never left
    /// gets — a Control Centre pull, an incoming call, a biometric sheet — so it
    /// still asks. A real return has already been answered a third of a second
    /// ago at `.inactive`, and asking again would be a second reading of the lock
    /// state that can only act on part of what it sees; see
    /// ``didEvaluateForeground``.
    func sceneBecameActive() {
        guard !didEvaluateForeground else {
            didEvaluateForeground = false
            return
        }
        enableAuth()
    }

    /// Engages the passcode lock: forgets the data key, then raises the overlay.
    ///
    /// Forgetting the key is what actually locks the app — the screen only
    /// reflects it. Without this the shares would stay readable behind the
    /// overlay and signing would still work.
    ///
    /// **Whether a gate is required is the caller's question**, asked as
    /// ``PasscodeService/isPasscodeGateRequired`` once, immediately before this.
    /// Re-deriving it here would mean the decision and the act came from two
    /// reads, and a passcode transition runs on `PasscodeService`'s executor
    /// rather than this one, so the second can disagree with the first: the
    /// caller would return past its own device-auth fallback believing a gate had
    /// gone up while this raised none, and the app would come back with neither.
    func raisePasscodeGate() {
        passcodeService.lock()
        passcodeGateGeneration &+= 1
        isPasscodeLocked = true
    }

    /// Takes the gate down when the passcode behind it is confirmed gone.
    ///
    /// ``isPasscodeLocked`` is a cache of ``PasscodeService/isPasscodeGateRequired``
    /// taken at the moment the gate went up, and one transition invalidates that
    /// cache in the worst way available. A `disablePasscode` that runs to
    /// completion across a background `lock()` leaves `.deviceAuth`, no wrapper,
    /// and a screen whose only exit is an unlock that can now answer nothing but
    /// `notSet` — nothing typed there is ever right, and force quitting is the
    /// only way out. So every path that can observe the gate while it is up
    /// re-derives the predicate rather than trusting the flag.
    ///
    /// Only a **confirmed** absence lowers it. An unreadable Keychain leaves the
    /// gate standing, because taking a real gate down over a momentary read
    /// failure is the one mistake available here that removes protection instead
    /// of restoring access.
    ///
    /// The caller is the lock screen, after an attempt that did not open the
    /// app: `unlockApp` repairs the lock mode when it finds the passcode
    /// confirmed gone, and this is what makes that repair visible to the person
    /// the gate is standing in front of.
    func lowerPasscodeGateIfNoLongerRequired() {
        guard !passcodeService.isPasscodeGateRequired else { return }
        isPasscodeLocked = false
    }

    /// Takes the lock screen down, but only if the session still holds the data
    /// key.
    ///
    /// The check sits here, immediately before the flag changes and with nothing
    /// between them, rather than in the caller. `PasscodeService.lock()` is
    /// `nonisolated` and synchronizes with nothing, so it can land after the
    /// unlock has verified and before the overlay is removed — and because the
    /// flag was already `true`, that lock leaves nothing behind to stop this
    /// assignment. The result would be balances and addresses on screen over a
    /// session that cannot sign.
    func markPasscodeUnlocked() {
        guard passcodeService.isSessionUnlocked else { return }
        isPasscodeLocked = false
    }

    /// Restores the lock on launch when a passcode is configured, so a cold start
    /// is gated rather than only a return from the background.
    ///
    /// **Called from `VultisigApp.init()`, before any view is built.** That is
    /// not a detail of where it was convenient to put it. From a view's
    /// `onAppear` this cannot win: the splash is a child of the view that would
    /// carry the modifier, a child's `onAppear` runs first, and the splash's
    /// first act is to authenticate and uncover the app. The gate then went up
    /// over an already-visible home screen. Deciding before the first body is
    /// evaluated also means the flag never transitions, so the overlay has
    /// nothing to animate and the first frame drawn is the lock screen.
    ///
    /// **Reconciliation runs first, synchronously, and that ordering is the
    /// point.** The lock mode lives in `UserDefaults` and the wrapped data key
    /// lives in the Keychain, and the two can disagree — `disablePasscode`
    /// changes the mode *before* deleting the wrapper precisely so an
    /// interruption leaves a repairable state rather than a gate with nothing
    /// behind it. `KeyshareInstallReconciler` is what repairs it, in both
    /// directions. It also runs at app `onAppear`, but nothing orders that
    /// against this, so the gate could be chosen from a mode reconciliation was
    /// about to change — after which the app sits open for the whole session
    /// with a wrapped key and no lock screen. Doing it here makes the ordering
    /// hold by construction instead of by luck; a second pass is a no-op,
    /// because the destructive half is marked once per container and the
    /// mode alignment only writes when it disagrees.
    ///
    /// The gate itself is then ``PasscodeService/isPasscodeGateRequired``, read
    /// *after* that repair rather than before it — reconciliation is precisely
    /// what can move the mode the predicate's first clause reads. A cold start
    /// with a persisted `.passcode` and a confirmed-absent wrapper therefore
    /// opens the app rather than presenting a lock screen no passcode can
    /// satisfy, and one whose Keychain merely did not answer still presents it.
    ///
    /// Reconciliation now also answers whether this device holds sealed key
    /// shares with no key left to open them, and that answer is taken **first**.
    /// The two cannot both be true — the orphaned state is only reported over a
    /// *confirmed absent* wrapper, which is exactly the reading that makes
    /// `isPasscodeGateRequired` false — so the ordering is not a race being
    /// resolved. It states which screen wins if that ever stops holding, and a
    /// lock screen no passcode can open is the wrong one.
    @MainActor
    func restorePasscodeLockOnLaunch() {
        let outcome = reconcileInstall()

        isKeyshareRecoveryRequired = outcome == .sealedSharesWithoutTheirKey
        guard !isKeyshareRecoveryRequired else {
            isPasscodeLocked = false
            return
        }

        guard passcodeService.isPasscodeGateRequired else {
            isPasscodeLocked = false
            return
        }
        raisePasscodeGate()
    }

    /// Asks to be sent from the recovery screen to the app's import flow.
    ///
    /// It only *asks*. The screen is hosted in a window above the app and has no
    /// access to its navigation, so the route is pushed by whoever owns the
    /// navigation stack — see ``handOffToKeyshareRecoveryImport(routingWith:)``.
    func beginKeyshareRecoveryImport() {
        guard isKeyshareRecoveryRequired else { return }
        isKeyshareRecoveryImportPending = true
    }

    /// Pushes the import route and only then takes the recovery screen down.
    ///
    /// **The order is the whole method.** Lowering first uncovers the app while
    /// the push is still on its way, so the wallet — the very thing this state
    /// exists to stop being shown as healthy — is what the user sees between the
    /// tap and the import screen. Routing first means the cover comes off a
    /// stack whose top is already where they were sent.
    ///
    /// **The screen does not come back if the user backs out of the import**,
    /// and that is a decision rather than an oversight. Re-raising it on the way
    /// out of that route would need the census taken again to tell a successful
    /// import from an abandoned one — and until the import path stops refusing
    /// the orphaned vault as a duplicate, "still orphaned" is the only answer it
    /// can give, which is a screen with no way out at all. This state is not a
    /// security boundary either: nothing behind it is protected, the app renders
    /// the same wallet with or without it and can sign in neither case. It is
    /// derived again on the next launch from the same census, so an import that
    /// succeeds no longer qualifies and one the user walked away from is put
    /// back in front of them.
    ///
    /// - Returns: whether this caller was the one that claimed the hand-off.
    ///   Every mounted scene sees the request, and two of them pushing the route
    ///   is two import screens.
    @discardableResult
    func handOffToKeyshareRecoveryImport(routingWith route: () -> Void) -> Bool {
        guard isKeyshareRecoveryImportPending else { return false }
        isKeyshareRecoveryImportPending = false
        route()
        isKeyshareRecoveryRequired = false
        return true
    }

    /// The foreground hook, and so the first place a transition that completed
    /// while the app was away becomes visible.
    ///
    /// Which gate this install has is asked as
    /// ``PasscodeService/isPasscodeGateRequired`` rather than read off
    /// `AppLockService.mode`, because here the two differing is not merely a gate
    /// nobody can open: a persisted `.passcode` over a confirmed-absent wrapper
    /// would take the passcode branch, raise nothing, and skip the device-auth
    /// re-lock as well — leaving the app open behind no gate at all. Asking the
    /// predicate routes that install onto the legacy path, which is the correct
    /// protection once there is no passcode.
    ///
    /// It is derived **once** and every branch acts on that one answer. The
    /// branch that returns past the device-auth fallback must never be entered on
    /// a `true` that has since become `false`, and a transition running on
    /// `PasscodeService`'s executor can make a second read disagree with the
    /// first — which is a foreground raising nothing and returning anyway.
    func enableAuth() {
        // The re-lock delay used to be five minutes hardcoded here, with no way
        // for anyone to change it. `AppLockService` owns that policy now.
        //
        // **A relock needs a backgrounding to be a relock *of* something.** The
        // interval measures time spent away, and an activation that follows no
        // departure has measured nothing — so the question is not even asked.
        // Short-circuiting matters as much as the answer: `evaluateForeground()`
        // rewrites the stored timestamp, and letting a Face ID sheet reset the
        // clock would move the moment the user actually left.
        let didBackground = didBackgroundSinceForeground
        didBackgroundSinceForeground = false
        let shouldRelock = didBackground && lockService.evaluateForeground()
        let gateRequired = passcodeService.isPasscodeGateRequired

        if gateRequired {
            // `!isPasscodeLocked` is not an optimisation. A biometric prompt
            // makes the app `.inactive` and then `.active` again, so this runs
            // *during* an unlock the user is in the middle of — and at the
            // `immediate` interval `shouldRelock` is unconditionally true.
            // Re-raising there calls `lock()` on the session the shortcut has
            // just opened and rebuilds the screen underneath it, which restarts
            // the prompt: a Face ID loop with no way out. A gate that is already
            // up needs nothing done to it.
            if shouldRelock, !isPasscodeLocked {
                // The lock goes up BEFORE the cover comes down. Dropping the
                // cover first left the home screen — balances, addresses —
                // visible for the frames it took the lock screen to mount, on
                // every single unlock.
                raisePasscodeGate()
            }
            showCover = false
            return
        }

        // The same rule as `lowerPasscodeGateIfNoLongerRequired()`, from the
        // answer already read: a gate raised before the app went away can be
        // standing over a passcode a disable removed while it was.
        isPasscodeLocked = false

        showCover = false
        guard shouldRelock else { return }

        if !didTriggerAuthThisSession {
            resetLogin()
            continueLogin()
        }
    }

    func getBiometricType() {
        let authContext = LAContext()
         _ = authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

        switch authContext.biometryType {
        case .none:
            authenticationType = .None
        case .touchID:
            authenticationType = .TouchID
        case .faceID:
            authenticationType = .FaceID
        case .opticID:
            authenticationType = .OpticID
        @unknown default:
            authenticationType = .None
        }
    }

    private func continueLogin() {
        guard !isAuthenticated else {
            return
        }

        guard !showOnboarding || isAuthenticationEnabled else {
            return
        }

        canLogin = true
        if !showSplashView {
            showSplashView = true
        }
    }

    private func resetLogin() {
        guard !showOnboarding || isAuthenticationEnabled else {
            return
        }

        canLogin = false
        isAuthenticated = false
        didUserCancelAuthentication = false
        showSplashView = true
    }
}

// MARK: - AccountLogic

struct AccountLogic {
    func isRunningOnPhysicalDevice() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif DEBUG
        return false
        #else
        return true
        #endif
    }
}
