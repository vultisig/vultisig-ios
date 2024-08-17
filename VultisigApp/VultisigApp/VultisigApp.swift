//
//  VultisigApp.swift
//  VultisigApp
//

import Mediator
import SwiftData
import SwiftUI
import WalletCore

@main

struct VultisigApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject var applicationState = ApplicationState.shared
    @StateObject var vaultDetailViewModel = VaultDetailViewModel()
    @StateObject var coinSelectionViewModel = CoinSelectionViewModel()
    @StateObject var accountViewModel = AccountViewModel()
    @StateObject var deeplinkViewModel = DeeplinkViewModel()
    @StateObject var settingsViewModel = SettingsViewModel.shared
    @StateObject var homeViewModel = HomeViewModel()
    @StateObject var settingsDefaultChainViewModel = SettingsDefaultChainViewModel()
    @StateObject var macCameraServiceViewModel = MacCameraServiceViewModel()
    
    init(){
        //setenv("GODEBUG", "asyncpreemptoff=1",1)
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(applicationState) // Shared monolithic mutable state
                .environmentObject(vaultDetailViewModel)
                .environmentObject(coinSelectionViewModel)
                .environmentObject(accountViewModel)
                .environmentObject(deeplinkViewModel)
                .environmentObject(settingsViewModel)
                .environmentObject(homeViewModel)
                .environmentObject(settingsDefaultChainViewModel)
                .environmentObject(macCameraServiceViewModel)
#if os(macOS)
                .onChange(of: scenePhase) {
                    switch scenePhase {
                    case .active:
                        continueLogin()
                    case .background:
                        resetLogin()
                    default:
                        break
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .frame(minWidth: 900, minHeight: 600)
                .onAppear{
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
#endif
        }
#if os(iOS)
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                continueLogin()
            case .background:
                resetLogin()
            default:
                break
            }
        }
#endif
        .modelContainer(sharedModelContainer)
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vault.self,
            Coin.self,
            DatabaseRate.self,
            AddressBookItem.self
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
    
    private func continueLogin() {
        accountViewModel.enableAuth()
    }
    
    private func resetLogin() {
        accountViewModel.revokeAuth()
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
