//
//  VultisigApp.swift
//  VultisigApp
//

import SwiftData
import SwiftUI
import WalletCore
import OSLog

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
    @StateObject var globalStateViewModel = GlobalStateViewModel()
    @StateObject var navigationRouter = NavigationRouter()
    @StateObject var sheetPresentedCounterManager = SheetPresentedCounterManager()
    @StateObject var pushNotificationManager = PushNotificationManager.shared

    init() {
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
        // Register every swap-tracking provider with the shared registry so
        // the tx-history viewmodel and the native status poller can route by
        // `providerKind`. New providers register here.
        SwapTrackingRegistry.shared.register(SwapKitTrackingService.shared)
    }
    var body: some Scene {
        WindowGroup {
            content
        }
        .modelContainer(sharedModelContainer)

        DocumentGroup(newDocument: VULTFileDocument()) { file in
            content
                .onAppear {
                    vultExtensionViewModel.documentData = file
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
            StoredPendingTransaction.self,
            VaultSettings.self,
            TransactionHistoryItem.self,
            SwapTrackingMetadata.self
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
            // Schema-breaking change in the swap-tracking refactor. Existing
            // tx-history rows from earlier builds of this branch carry the
            // old 10-column `swapKit*` shape and won't load against the new
            // relationship-based schema. Wipe the on-disk store and retry —
            // testers reinstall anyway, this is the belt-and-suspenders path
            // so the app at least launches cleanly on first relaunch after
            // upgrade rather than crashing on a schema-mismatch error.
            if let storeURL = modelConfiguration.url as URL? {
                try? FileManager.default.removeItem(at: storeURL)
                // SwiftData writes -shm / -wal companions alongside the
                // SQLite store; drop them too so the retry sees a clean slate.
                let shm = storeURL.appendingPathExtension("shm")
                let wal = storeURL.appendingPathExtension("wal")
                try? FileManager.default.removeItem(at: shm)
                try? FileManager.default.removeItem(at: wal)
            }
            do {
                let modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: MigrationPlan.self,
                    configurations: [modelConfiguration]
                )
                Storage.shared.modelContext = modelContainer.mainContext
                return modelContainer
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
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
            .environmentObject(globalStateViewModel)
            .environmentObject(sheetPresentedCounterManager)
            .environmentObject(homeViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(pushNotificationManager)
            .onChange(of: scenePhase) {
                switch scenePhase {
                case .active:
                    continueLogin()
                    appViewModel.refreshFastVaultEligibilityIfNeeded()
                    Task { @MainActor in
                        SwapTrackingRegistry.shared.setActiveOnAll(true)
                        await SwapTrackingRegistry.shared.resumeAllInFlight()
                    }
                case .background:
                    resetLogin()
                    Task { @MainActor in
                        SwapTrackingRegistry.shared.setActiveOnAll(false)
                    }
                default:
                    break
                }
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-disableAnimations") {
                    UIView.setAnimationsEnabled(false)
                }
                #endif

                // Run migrations on app launch
                AppMigrationService().performMigrationsIfNeeded()

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
            .environmentObject(globalStateViewModel)
            .environmentObject(sheetPresentedCounterManager)
            .environmentObject(homeViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(pushNotificationManager)
            .buttonStyle(BorderlessButtonStyle())
            .frame(minWidth: 900, minHeight: 600)
            .onAppear {
                // Run migrations on app launch
                AppMigrationService().performMigrationsIfNeeded()

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
