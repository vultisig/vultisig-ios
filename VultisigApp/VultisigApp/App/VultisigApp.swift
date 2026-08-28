//
//  VultisigApp.swift
//  VultisigApp
//

import SwiftData
import SwiftUI
import WalletCore
import OSLog
import VultisigUIResources

@main
struct VultisigApp: App {
    @Environment(\.scenePhase) var scenePhase

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

    @StateObject var applicationState = ApplicationState.shared
    @StateObject var vaultDetailViewModel = VaultDetailViewModel()
    @StateObject var coinSelectionViewModel = CoinSelectionViewModel()
    @StateObject var appViewModel = AppViewModel.shared
    @StateObject var deeplinkViewModel = DeeplinkViewModel()
    @StateObject var settingsViewModel = SettingsViewModel.shared
    @StateObject var homeViewModel = HomeViewModel()
    @StateObject var vultExtensionViewModel = VultExtensionViewModel()
    @StateObject var phoneCheckUpdateViewModel = PhoneCheckUpdateViewModel()
    @StateObject var navigationRouter = NavigationRouter()
    @StateObject var sheetPresentedCounterManager = SheetPresentedCounterManager()
    @StateObject var pushNotificationManager = PushNotificationManager.shared

    init() {
        VultisigResources.registerFonts()

#if os(macOS)
        // Check for --version flag
        if CommandLine.arguments.contains("--version") {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                print("VultisigApp version \(version) (build \(build))")
            } else {
                print("Version information not available")
            }
            exit(0) // Exit after printing version
        }
#endif
        // The launch gate is decided here, before a single view exists.
        //
        // It used to be decided from `ContentView`'s `onLoad`, and that lost a
        // race it could not win: `WelcomeView` is a *child* of the view carrying
        // that modifier, SwiftUI runs a child's `onAppear` before its parent's,
        // and the first thing `WelcomeView` does is authenticate and take the
        // splash down. So the home screen — balances, addresses — was uncovered
        // by the child before the parent had decided whether to lock, and the
        // lock screen then faded in over it.
        //
        // Doing it in the app's initializer removes the race rather than
        // reordering it. Stored properties with initializers run before this
        // body, so `sharedModelContainer` has already installed
        // `Storage.shared.modelContext` and reconciliation can read the vault
        // store — which is the ordering `restorePasscodeLockOnLaunch()` requires
        // and documents. And because the flag is already `true` when the first
        // body is evaluated, there is no false-to-true transition for the
        // overlay's animation to fade: the app's first frame is the lock screen.
        AppViewModel.shared.restorePasscodeLockOnLaunch()

        // Register every swap-tracking provider with the shared registry so
        // the tx-history viewmodel and the native status poller can route by
        // `providerKind`. New providers register here.
        SwapTrackingRegistry.shared.register(SwapKitTrackingService.shared)
        SwapTrackingRegistry.shared.register(THORChainLimitTrackingService.shared)

        // Register every destination-token provider with the swap destination
        // registry so the swap coin picker can aggregate destination tokens from
        // every source. New destination providers register here.
        TokenCatalogRepository.shared.register(SwapKitTokensCache.shared)
        TokenCatalogRepository.shared.register(NativePoolTokenProvider(proto: .thorchain))
        TokenCatalogRepository.shared.register(NativePoolTokenProvider(proto: .mayachain))
        TokenCatalogRepository.shared.register(SecuredAssetTokenProvider())

        // Register the app-wide token catalog providers (wallet search /
        // add-token). Bundled `TokensStore` is the highest-precedence, curated,
        // offline floor; dynamic sources (1inch / Jupiter) register on top.
        TokenCatalogRepository.appCatalog.register(BundledTokensProvider.shared)
        TokenCatalogRepository.appCatalog.register(OneInchCatalogProvider.shared)
        TokenCatalogRepository.appCatalog.register(JupiterCatalogProvider.shared)
    }
    var body: some Scene {
        WindowGroup {
            content
        }
        .modelContainer(sharedModelContainer)

        DocumentGroup(newDocument: VULTFileDocument()) { file in
            content
                // The one file-entry route that does not go through
                // `ContentView.handleDeeplink`, and so the one that was not
                // queued behind the lock. A password-protected `.vult` opened
                // from Files while the app is locked ends in a UIKit password
                // alert on the key window — over the lock screen, taking input.
                .presentsWhenUnlocked {
                    vultExtensionViewModel.handOff(documentData: file)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vault.self,
            Coin.self,
            DatabaseRate.self,
            AddressBookItem.self,
            Folder.self,
            HiddenToken.self,
            ReferralCode.self,
            ReferredCode.self,
            DefiPositions.self,
            BondPosition.self,
            StakePosition.self,
            LPPosition.self,
            CirclePosition.self,
            YieldPosition.self,
            YieldRedemptionRecord.self,
            KaminoPosition.self,
            StoredPendingTransaction.self,
            VaultSettings.self,
            TransactionHistoryItem.self,
            SwapTrackingMetadata.self,
            CustomRPCOverride.self,
            LimitOrder.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            let modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: MigrationPlan.self,
                configurations: [modelConfiguration]
            )
            Storage.shared.modelContext = modelContainer.mainContext

            return modelContainer
        } catch {
            // NEVER wipe the store on migration failure — that destroys user
            // vaults. SwiftData's lightweight migration handles all additive
            // changes (new models, new optional relationships) automatically.
            // If we ever need a destructive schema change, add an explicit
            // SchemaMigrationPlan stage rather than silently nuking the DB.
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    func continueLogin() {
        appViewModel.enableAuth()
    }

    func resetLogin() {
        appViewModel.revokeAuth()
    }
}

private extension VultisigApp {

    enum SchemaV1: VersionedSchema {
        static var versionIdentifier = Schema.Version(1, 0, 0)

        static var models: [any PersistentModel.Type] {
            [Vault.self, Coin.self]
        }
    }

    enum MigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            return [SchemaV1.self]
        }

        static var stages: [MigrationStage] {
            return []
        }
    }
}
extension ModelContext {
    var sqliteCommand: String {
        if let url = container.configurations.first?.url.path(percentEncoded: false) {
            "sqlite3 \"\(url)\""
        } else {
            "No SQLite database found."
        }
    }
}

#if os(iOS)
import SwiftUI

extension VultisigApp {
    var content: some View {
        ContentView(navigationRouter: navigationRouter)
            .environmentObject(applicationState) // Shared monolithic mutable state
            .environmentObject(vaultDetailViewModel)
            .environmentObject(appViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(vultExtensionViewModel)
            .environmentObject(phoneCheckUpdateViewModel)
            .environmentObject(sheetPresentedCounterManager)
            .environmentObject(homeViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(pushNotificationManager)
            .appReviewPromptHost()
            .onChange(of: scenePhase) { previousPhase, newPhase in
                switch newPhase {
                case .active:
                    // Not `continueLogin()` directly: a return was decided at
                    // `.inactive` and must not be decided again here — see
                    // `AppViewModel.sceneBecameActive()`.
                    appViewModel.sceneBecameActive()
                    appViewModel.refreshFastVaultEligibilityIfNeeded()
                    Task { @MainActor in
                        SwapTrackingRegistry.shared.setActiveOnAll(true)
                        await SwapTrackingRegistry.shared.resumeAllInFlight()
                    }
                case .inactive:
                    // The picture is taken one step ahead of the cover that
                    // shows it, so that the first covered frame already has it
                    // — see `PrivacyBackdrop.take()`. Only on the way out: a
                    // return is about to uncover, and photographing the app
                    // there would be work thrown away.
                    if previousPhase == .active {
                        PrivacyBackdrop.take()
                    }
                    // Leaving and returning are the same phase, and which one
                    // this is decides whether the cover goes up or comes down —
                    // see `AppViewModel.sceneBecameInactive(comingFrom:)`.
                    appViewModel.sceneBecameInactive(comingFrom: previousPhase)
                case .background:
                    resetLogin()
                    Task { @MainActor in
                        SwapTrackingRegistry.shared.setActiveOnAll(false)
                    }
                @unknown default:
                    break
                }
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-disableAnimations") {
                    UIView.setAnimationsEnabled(false)
                }
                #endif

                // Reconciliation is NOT repeated here. It ran in `init()`,
                // strictly earlier in the same process, and the launch gate was
                // derived from its result — so a second raw pass is not a
                // harmless retry, it is a second decision nothing reconciles
                // with the first. It can move the lock mode after
                // `isPasscodeLocked` has already been settled from the old one,
                // which leaves the app either open for the whole session with a
                // wrapper and no gate, or behind an overlay whose passcode is
                // gone.
                //
                // What is given up by dropping it is a same-launch retry, and
                // the trade is deliberate. One of reconciliation's two deferrals
                // genuinely cannot happen here — no transition has started by
                // `init()`, so the lease is always free. The other one can:
                // `storeOccupancy` reads the vault count through `try?`, and a
                // `fetchCount` that throws still answers `.unknown` however early
                // it is asked. In that case the inherited-material clear waits for
                // the next cold launch while lock-mode alignment still runs, so a
                // new container over a previous install's wrapper can sit behind a
                // gate its passcode cannot open until the app is relaunched.
                //
                // That is recoverable and it is rare. A competing decision is
                // neither: it silently leaves the app open all session with a
                // wrapper and no gate. A retry that runs milliseconds later, from
                // a read that just failed, is not worth buying that with.

                // Run migrations on app launch
                AppMigrationService().performMigrationsIfNeeded()

                // Hydrate the custom-RPC in-memory mirror from SwiftData so
                // overrides survive relaunch and the off-MainActor networking
                // funnel can read them without touching @Model.
                CustomRPCStore.shared.reloadFromStore()

                // Stamp the install date the App Store review throttle waits
                // on. Idempotent, and deliberately placed at launch rather
                // than at the first confirmed transaction: the 7-day rule has
                // to be measured from when the user got the app, not from
                // when they first happened to transact.
                AppReviewService.shared.seedInstallDateIfNeeded()

                if ProcessInfo.processInfo.isiOSAppOnMac {
                    continueLogin()
                }

                #if DEBUG
                guard !CommandLine.arguments.contains("-UITesting") else { return }
                #endif

                Task {
                    await pushNotificationManager.checkPermissionStatus()
                    if pushNotificationManager.isPermissionGranted {
                        pushNotificationManager.registerForRemoteNotifications()
                    }
                }

                Task { @MainActor in
                    await SwapTrackingRegistry.shared.resumeAllInFlight()
                }
            }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension VultisigApp {
    var content: some View {
        ContentView(navigationRouter: navigationRouter)
            .environmentObject(applicationState) // Shared monolithic mutable state
            .environmentObject(vaultDetailViewModel)
            .environmentObject(appViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(vultExtensionViewModel)
            .environmentObject(phoneCheckUpdateViewModel)
            .environmentObject(sheetPresentedCounterManager)
            .environmentObject(homeViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(pushNotificationManager)
            .buttonStyle(BorderlessButtonStyle())
            .frame(minWidth: 900, minHeight: 600)
            // macOS does not reliably report scenePhase `.background` when the
            // app is hidden or switched away from, so the shared scene-phase
            // hook would seldom fire and the lock would seldom engage. AppKit's
            // activation notifications are the dependable signal here.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                resetLogin()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                continueLogin()
            }
            .onAppear {
                // Reconciliation is NOT repeated here. It ran in `init()`,
                // strictly earlier in the same process, and the launch gate was
                // derived from its result — so a second raw pass is not a
                // harmless retry, it is a second decision nothing reconciles
                // with the first. It can move the lock mode after
                // `isPasscodeLocked` has already been settled from the old one,
                // which leaves the app either open for the whole session with a
                // wrapper and no gate, or behind an overlay whose passcode is
                // gone.
                //
                // What is given up by dropping it is a same-launch retry, and
                // the trade is deliberate. One of reconciliation's two deferrals
                // genuinely cannot happen here — no transition has started by
                // `init()`, so the lease is always free. The other one can:
                // `storeOccupancy` reads the vault count through `try?`, and a
                // `fetchCount` that throws still answers `.unknown` however early
                // it is asked. In that case the inherited-material clear waits for
                // the next cold launch while lock-mode alignment still runs, so a
                // new container over a previous install's wrapper can sit behind a
                // gate its passcode cannot open until the app is relaunched.
                //
                // That is recoverable and it is rare. A competing decision is
                // neither: it silently leaves the app open all session with a
                // wrapper and no gate. A retry that runs milliseconds later, from
                // a read that just failed, is not worth buying that with.

                // Run migrations on app launch
                AppMigrationService().performMigrationsIfNeeded()

                // Hydrate the custom-RPC in-memory mirror from SwiftData so
                // overrides survive relaunch and the off-MainActor networking
                // funnel can read them without touching @Model.
                CustomRPCStore.shared.reloadFromStore()

                NSWindow.allowsAutomaticWindowTabbing = false
                continueLogin()

                Task {
                    await pushNotificationManager.checkPermissionStatus()
                    if pushNotificationManager.isPermissionGranted {
                        pushNotificationManager.registerForRemoteNotifications()
                    }
                }

                Task { @MainActor in
                    await SwapTrackingRegistry.shared.resumeAllInFlight()
                }
            }
    }
}
#endif
