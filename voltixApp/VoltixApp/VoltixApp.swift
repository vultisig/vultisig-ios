//
//  VoltixApp.swift
//  VoltixApp
//

import Mediator
import SwiftData
import SwiftUI
import WalletCore
import SDWebImageSVGCoder

@main
struct VoltixApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject var coinViewModel = CoinViewModel()
    @StateObject var applicationState = ApplicationState.shared
    @StateObject var vaultDetailViewModel = VaultDetailViewModel()
    
    init() {
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
    }

    var body: some Scene {
        WindowGroup {
            MainNavigationStack()
                .environmentObject(coinViewModel)
                .environmentObject(applicationState) // Shared monolithic mutable state
                .environmentObject(vaultDetailViewModel)
        }
        .modelContainer(sharedModelContainer)
//        .onChange(of: scenePhase) { phase in
//            if phase == .inactive {
//                // TODO: Anything that needs doing on app backgrounded.
//            }
//        }
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
}
