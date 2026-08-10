//
//  ContentView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import SwiftData

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
        .onChange(of: appViewModel.isPasscodeLocked) { _, isLocked in
            guard !isLocked else { return }
            drainPendingDeeplinks()
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
        .overlay(appViewModel.showCover ? CoverView() : nil)
        .overlay(passcodeGate.animation(.easeInOut(duration: 0.25), value: appViewModel.isPasscodeLocked))
        // Additive to the two overlays above, not a replacement for them. The
        // overlays are what the app draws; the window is what reaches the layer
        // sheets and alerts are presented in, which no overlay can.
        .hostsAppLock(
            appLockPresentation,
            onUnlocked: { appViewModel.markPasscodeUnlocked() },
            onAttemptFailed: { appViewModel.lowerPasscodeGateIfNoLongerRequired() }
        )
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

    /// What the app is covering itself with, as one value — see
    /// ``AppLockPresentation``.
    private var appLockPresentation: AppLockPresentation {
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

    /// Deeplinks are held until the app is unlocked.
    ///
    /// Acting on one while locked would navigate, present sheets and mutate
    /// state behind the lock screen — the gate has to apply to what the app
    /// *does*, not only to what it shows.
    private func handleDeeplink(_ incomingURL: URL) {
        guard !appViewModel.isPasscodeLocked else {
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
