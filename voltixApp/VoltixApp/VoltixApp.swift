//
//  VoltixApp.swift
//  VoltixApp
//

import Mediator
import SwiftData
import SwiftUI
import WalletCore

@main
struct VoltixApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject var coinViewModel = CoinViewModel()
    @StateObject var applicationState = ApplicationState.shared
    @StateObject var vaultDetailViewModel = VaultDetailViewModel()
    @StateObject var tokenSelectionViewModel = TokenSelectionViewModel()
    @StateObject var accountViewModel = AccountViewModel()
    @StateObject var deeplinkViewModel = DeeplinkViewModel()
    @StateObject var settingsViewModel = SettingsViewModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coinViewModel)
                .environmentObject(applicationState) // Shared monolithic mutable state
                .environmentObject(vaultDetailViewModel)
                .environmentObject(tokenSelectionViewModel)
                .environmentObject(accountViewModel)
                .environmentObject(deeplinkViewModel)
                .environmentObject(settingsViewModel)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                continueLogin()
            case .inactive, .background:
                resetLogin()
            default:
                break
            }
        }
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vault.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    private func continueLogin() {
        accountViewModel.continueLogin()
    }
    
    private func resetLogin() {
        accountViewModel.resetLogin()
    }
}
