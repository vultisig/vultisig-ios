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
    @StateObject var coinService = CoinService.shared

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
            StoredPendingTransaction.self
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
