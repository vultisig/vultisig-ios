//
//  ContentView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import SwiftData

private let logger = Log.app.other

enum RootRoute {
    case home(showingVaultSelector: Bool)
    case createVault
}

struct ContentView: View {
    @Query var vaults: [Vault]

    @ObservedObject var navigationRouter: NavigationRouter
    @StateObject var router: VultisigRouter
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var pushNotificationManager: PushNotificationManager
    @Environment(\.sheetPresentedCounterManager) var sheetPresentedCounterManager
    @ObservedObject private var appLockHost = AppLockHost.shared

    @State private var rootRoute: RootRoute?
    @State private var deeplinkError: Error?
    @State private var pendingDeeplinks: [URL] = []
    @State private var dismissSplashTask: Task<Void, Never>?

    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self._router = StateObject(wrappedValue: VultisigRouter(navigationRouter: navigationRouter))
    }

    var body: some View {
        NavigationStack(path: $navigationRouter.navPath) {
            ZStack {
                if appViewModel.showSplashView {
                    splashView
                } else {
                    container
                        .background(Theme.colors.bgPrimary)
                }
            }
            .navigationDestination(for: HomeRoute.self) { router.homeRouter.build($0) }
            .navigationDestination(for: SendRoute.self) { router.sendRouter.build($0) }
            .navigationDestination(for: SwapRoute.self) { router.swapRouter.build($0) }
            .navigationDestination(for: KeygenRoute.self) { router.keygenRouter.build($0) }
            .navigationDestination(for: VaultRoute.self) { router.vaultRouter.build($0) }
            .navigationDestination(for: OnboardingRoute.self) { router.onboardingRouter.build($0) }
            .navigationDestination(for: ReferralRoute.self) { router.referralRouter.build($0) }
            .navigationDestination(for: FunctionCallRoute.self) { router.functionCallRouter.build($0) }
            .navigationDestination(for: SigningRoute.self) { router.signingRouter.build($0) }
            .navigationDestination(for: SettingsRoute.self) { router.settingsRouter.build($0) }
            .navigationDestination(for: YieldRoute.self) { router.yieldRouter.build($0) }
            .navigationDestination(for: KaminoRoute.self) { router.kaminoRouter.build($0) }
            .navigationDestination(for: TronRoute.self) { router.tronRouter.build($0) }
            .navigationDestination(for: TransactionHistoryRoute.self) { router.transactionHistoryRouter.build($0) }
            .navigationDestination(for: QBTCClaimRoute.self) { route in
                // Defense-in-depth — `QBTCClaimRoute` subroutes (pair /
                // keysign / done) are only pushed from `QBTCClaimScreen`
                // and its children, which themselves require the QBTC
                // feature flag. Guarding here too prevents any future
                // code path from rendering a QBTC sub-screen behind the
                // flag's back.
                if QBTCConfig.isFeatureEnabled {
                    router.qbtcClaimRouter.build(route)
                } else {
                    EmptyView()
                }
            }
        }
        .environment(\.router, router.navigationRouter)
        .colorScheme(.dark)
        .accentColor(.white)
        .sheetPresentedStyle()
        .onOpenURL { incomingURL in
            handleDeeplink(incomingURL)
        }
        // Either cover, not just the gate: a deeplink acted on behind the
        // recovery screen navigates and presents where nobody can see it, and
        // then lands the user somewhere other than the import flow the moment
        // that screen comes down.
        .onChange(of: appViewModel.isCoveredByAppLock) { _, isCovered in
            guard !isCovered else { return }
            drainPendingDeeplinks()
        }
        // The document scene's hand-off is owned here rather than by `HomeScreen`,
        // because `HomeScreen` is not always there: an install with no vaults
        // routes straight to create-vault, and a `.vult` opened from Files then
        // had nothing listening at all — the user's backup never opened. This view
        // is mounted in every scene the app can open, and for the whole of each.
        //
        // A trigger rather than a subscription on the flag: `@Published` publishes
        // from `willSet`, so anything that reacts by *reading* the flag reads the
        // value from before the hand-off, declines, and leaves it raised with
        // nobody left to ask. `consumeDocumentImport()` is what keeps a second
        // mounted scene from pushing the same route twice.
        .presentsWhenUnlocked(on: vultExtensionViewModel.isDocumentImportPending) {
            guard vultExtensionViewModel.consumeDocumentImport() else { return }
            navigationRouter.navigate(to: OnboardingRoute.importVaultShare)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name("HandlePushNotification")
            )
        ) { notification in
            guard let url = notification.object as? URL else { return }
            handleDeeplink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            if let incomingURL = userActivity.webpageURL {
                handleDeeplink(incomingURL)
            }
        }
        // Below the two overlays, and that is the whole reason it moved. The
        // banner modifier wraps what it is applied to in a `VStack` rather than
        // layering over it, so applied *after* the gate it is a sibling of the
        // gate — it pushed the lock screen down the display and drew a decoded
        // keysign summary in the space it vacated. Applied before, the overlays
        // cover it like anything else.
        .withForegroundNotificationBanner()
        // The same picture the raised window shows, not a second opinion. This
        // overlay renders in the pass that raises the cover and the window is put
        // up after it, so anything different here is a frame of something else
        // on the way out — which is how a logo came to flash over the wallet.
        .overlay(appViewModel.showCover ? CoverView(backdrop: privacyBackdrop) : nil)
        .overlay(passcodeGate.animation(.easeInOut(duration: 0.25), value: appViewModel.isPasscodeLocked))
        // Above the gate's overlay, matching the order `appLockPresentation`
        // derives: the two are mutually exclusive today, and if that ever stops
        // being true the screen a passcode cannot dismiss must not be the one
        // underneath.
        .overlay(keyshareRecoveryFloor)
        // Additive to the overlays above, not a replacement for them. The
        // overlays are what the app draws; the window is what reaches the layer
        // sheets and alerts are presented in, which no overlay can.
        .hostsAppLock(
            appLockPresentation,
            onUnlocked: { appViewModel.markPasscodeUnlocked() },
            onAttemptFailed: { appViewModel.lowerPasscodeGateIfNoLongerRequired() },
            onRestoreFromBackup: { appViewModel.beginKeyshareRecoveryImport() }
        )
        // The recovery screen points at the import flow, and the import flow is
        // a screen in this navigation stack — which the recovery screen is
        // drawn over, in a window it cannot reach. So it asks, and this routes.
        .onChange(of: appViewModel.isKeyshareRecoveryImportPending) { _, isPending in
            guard isPending else { return }
            appViewModel.handOffToKeyshareRecoveryImport {
                appViewModel.showSplashView = false
                // A `.vult` opened from Files while the recovery screen was up
                // is pending this very route, and its hold runs the moment the
                // cover comes down. Claimed here so that becomes a no-op rather
                // than a second copy of the import screen on the stack — the
                // document itself is still on the view model, and the import
                // screen picks it up when it appears.
                _ = vultExtensionViewModel.consumeDocumentImport()
                // Without animation, and that is not a style choice: the push
                // slides for a third of a second, and the recovery screen comes
                // off as soon as this returns. Animated, that third of a second
                // is the wallet on screen behind a transition — which is the
                // silent open this state exists to prevent, arriving by the one
                // door left open.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    navigationRouter.navigate(to: OnboardingRoute.importVaultShare)
                }
            }
        }
        .onLoad {
            // The cold-start gate is not decided here. It is decided in
            // `VultisigApp.init()`, because this modifier runs *after* the
            // splash child's `onAppear` has already taken the splash down.
            pushNotificationManager.hadVaultsOnStartup = !vaults.isEmpty

            if vaults.isEmpty {
                appViewModel.showSplashView = false
                rootRoute = .createVault
            } else {
                appViewModel.loadSelectedVault(for: vaults)
            }

            // Resume polling for pending transactions on app launch
            Task {
                BackgroundTransactionPoller.shared.resumePendingTransactions()
            }
        }
        .onChange(of: appViewModel.selectedVault) { _, _ in
            guard appViewModel.restartNavigation else { return }
            navigateToHome()
        }
        .onChange(of: appViewModel.restartNavigation) { _, newValue in
            guard newValue else { return }
            navigateToHome()
            appViewModel.restartNavigation = false
        }
        .onChange(of: appViewModel.showSplashView) { oldValue, newValue in
            // Clear any orphaned sheet blur counter when transitioning from splash to main content.
            // No sheets can be presenting at this moment (home screen hasn't loaded yet),
            // so any counter > 0 is stale from a previous session's view lifecycle.
            if oldValue && !newValue {
                sheetPresentedCounterManager.resetCounter()
            }
        }
        .withError(error: $deeplinkError, errorType: .warning) {
            // Retry action - clear error to allow user to try again
            deeplinkError = nil
        }
    }

    /// The blurred picture of the app that the privacy cover shows, where there
    /// is one to show.
    ///
    /// Read rather than observed, and that is sound because of when it is
    /// written: the picture is taken one step *ahead* of `showCover`, so by the
    /// time this body runs in response to the flag it is already there. Nothing
    /// changes it while the cover is up.
    ///
    /// The Mac has none — no app switcher zooms a stale card up there, so the
    /// cover stays the brand screen.
    private var privacyBackdrop: Image? {
        #if os(iOS)
        return PrivacyBackdrop.latest
        #else
        return nil
        #endif
    }

    /// What the app is covering itself with, as one value — see
    /// ``AppLockPresentation``.
    private var appLockPresentation: AppLockPresentation {
        if appViewModel.isKeyshareRecoveryRequired {
            return .recovery
        }
        if appViewModel.isPasscodeLocked {
            return .gate(generation: appViewModel.passcodeGateGeneration)
        }
        return appViewModel.showCover ? .cover : .uncovered
    }

    /// Covers the app while the passcode lock is engaged. An overlay rather than
    /// a navigation destination, so no route, deeplink or restored screen can
    /// appear instead of it.
    ///
    /// **The overlay is the floor, not the lock.** SwiftUI presents sheets and
    /// full-screen covers in a layer an overlay does not reach, so the lock
    /// screen itself is hosted in a window above that layer — see
    /// ``SwiftUI/View/hostsAppLock(_:onUnlocked:onAttemptFailed:)``. The overlay
    /// stays because the window cannot cover the cold start: a `UIWindow` needs a
    /// `UIWindowScene`, and the gate is decided in `VultisigApp.init()`, before
    /// any scene exists. This is what makes the first frame drawn the lock screen
    /// rather than the wallet.
    @ViewBuilder
    var passcodeGate: some View {
        if appViewModel.isPasscodeLocked {
            gateContent
                // No `.ignoresSafeArea()` here, and it has to stay that way: the
                // keypad's `Screen` already paints its background full-bleed
                // while keeping content inside the safe area, and ignoring it at
                // this level pushed the title under the Dynamic Island. The
                // screen's *other* half — the brand screen shown while biometrics
                // are tried — ignores it internally, which is what makes that
                // half line up with the privacy cover rather than sitting twelve
                // points off it.
                //
                // **Asymmetric, and the insertion side is the point.** A lock
                // that fades in is a lock you can see through while it arrives:
                // the foreground path raises the gate and drops the privacy cover
                // in one update, so a 0.25s fade renders the home screen —
                // balances, addresses — underneath for the whole of it. Going up
                // is instant. Coming down still fades, because by then the app is
                // unlocked and there is nothing left to hide.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                // A raise is a new screen, never a reused one. See
                // ``AppViewModel/passcodeGateGeneration``.
                .id(appViewModel.passcodeGateGeneration)
        }
    }

    /// Exactly one of these mounts an interactive lock screen, and which one is
    /// the host's to say.
    ///
    /// ``EnterPasscodeScreen`` starts a biometric attempt from its `.task`, so a
    /// second live copy is a second Face ID prompt. When the window is carrying
    /// the lock, this draws the brand screen instead — the same pixels the lock
    /// screen itself shows while that attempt runs, so nothing moves if the two
    /// are ever seen in sequence — and it is only there to stop the wallet being
    /// visible underneath.
    @ViewBuilder
    private var gateContent: some View {
        if appLockHost.hostsLockScreen {
            VultisigBrandScreen()
        } else {
            EnterPasscodeScreen(
                onUnlocked: { appViewModel.markPasscodeUnlocked() },
                onAttemptFailed: { appViewModel.lowerPasscodeGateIfNoLongerRequired() }
            )
        }
    }

    /// Covers the app when this device holds sealed key shares and the key that
    /// opens them is confirmed gone.
    ///
    /// The same floor-and-window split as ``passcodeGate``, and for the same
    /// reason: the window reaches the layer sheets are presented in and the
    /// overlay covers the cold start, where the recovery state is decided
    /// before any scene — and so any window — exists. Exactly one of them
    /// mounts the live screen, and which one is the host's to say.
    ///
    /// No transition and no identity. It is derived once at launch rather than
    /// raised and re-raised, so there is nothing for either to disambiguate.
    @ViewBuilder
    var keyshareRecoveryFloor: some View {
        if appViewModel.isKeyshareRecoveryRequired {
            if appLockHost.hostsLockScreen {
                VultisigBrandScreen()
            } else {
                KeyshareRecoveryScreen(
                    onRestoreFromBackup: { appViewModel.beginKeyshareRecoveryImport() }
                )
            }
        }
    }

    func navigateToHome() {
        appViewModel.showSplashView = false
        rootRoute = .home(showingVaultSelector: appViewModel.showingVaultSelector)
        navigationRouter.navPath = NavigationPath()
    }

    @ViewBuilder
    var content: some View {
        switch rootRoute {
        case .home(let showingVaultSelector):
            router.homeRouter.build(.home(showingVaultSelector: showingVaultSelector))
        case .createVault:
            router.vaultRouter.build(.createVault(showBackButton: false))
        case .none:
            CoverView()
        }
    }

    var splashView: some View {
        WelcomeView()
            .onAppear {
                setData()
            }
            .onChange(of: appViewModel.canLogin) { _, newValue in
                if newValue {
                    authenticateUser()
                }
            }
    }

    private func setData() {
        authenticateUser()
    }

    private func authenticateUser() {
        guard appViewModel.canLogin else {
            return
        }

        guard !appViewModel.didUserCancelAuthentication else {
            return
        }

        guard !appViewModel.showOnboarding && !vaults.isEmpty else {
            dismissSplashTask?.cancel()
            dismissSplashTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                appViewModel.showSplashView = false
            }
            return
        }

        appViewModel.authenticateUser()
    }

    /// Deeplinks are held until the app is showing itself again.
    ///
    /// Acting on one behind a cover would navigate, present sheets and mutate
    /// state where nobody can see it — a cover has to apply to what the app
    /// *does*, not only to what it shows.
    ///
    /// **Held behind the lock screen, dropped behind the recovery screen**, and
    /// the difference is how long each one lasts. A gate is seconds, so a link
    /// is worth keeping. The recovery screen stands for the rest of the session
    /// and comes down onto the import flow, so a link kept there would arrive an
    /// arbitrary time later, on top of the one screen the user asked for. The
    /// queue is also `@State`, so it is per scene — dropping needs no
    /// co-ordination between them, where draining would.
    private func handleDeeplink(_ incomingURL: URL) {
        guard !appViewModel.isKeyshareRecoveryRequired else {
            logger.info("Ignoring a deeplink that arrived while the key-share recovery screen was up")
            return
        }
        guard !appViewModel.isCoveredByAppLock else {
            // Queued rather than replaced: a single slot silently drops every
            // link but the last, and each one is a user action.
            pendingDeeplinks.append(incomingURL)
            return
        }
        processDeeplink(incomingURL)
    }

    private func drainPendingDeeplinks() {
        let queued = pendingDeeplinks
        pendingDeeplinks = []
        queued.forEach(processDeeplink)
    }

    private func processDeeplink(_ incomingURL: URL) {
        guard let deeplinkType = incomingURL.absoluteString.split(separator: ":").first else {
            return
        }

        if deeplinkType == "file" {
            vultExtensionViewModel.documentUrl = incomingURL
            vultExtensionViewModel.showImportView = true
        } else if deeplinkType == "https" {
            let updatedURL = incomingURL.absoluteString.replacingOccurrences(of: "https", with: "vultisig")

            guard let url = URL(string: updatedURL) else {
                return
            }

           handleDeepLinkURL(url)
        } else {
            handleDeepLinkURL(incomingURL)
        }

        guard deeplinkError == nil else { return }

        NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)

            if deeplinkViewModel.type != nil {
                NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
            }
        }
    }

    private func handleDeepLinkURL(_ url: URL) {
        do {
            try deeplinkViewModel.extractParameters(url, vaults: vaults)
            deeplinkError = nil
        } catch {
            deeplinkError = error
        }
    }
}

#Preview {
    ContentView(navigationRouter: .init())
        .environmentObject(AppViewModel())
        .environmentObject(ApplicationState())
        .environmentObject(HomeViewModel())
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(DeeplinkViewModel())
}

#if os(iOS)
import SwiftUI

extension ContentView {
    var container: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarTitleTextColor(Theme.colors.textPrimary)
            .onChange(of: vultExtensionViewModel.showImportView) { _, shouldNavigate in
                guard shouldNavigate else { return }
                navigationRouter.navigate(to: OnboardingRoute.importVaultShare)
                vultExtensionViewModel.showImportView = false
            }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension ContentView {
    var container: some View {
        content
            .navigationTitle("Vultisig")
    }
}
#endif
