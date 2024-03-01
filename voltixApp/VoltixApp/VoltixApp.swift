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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vault.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        SolanaHelper.test(pubKey: "420016ebef7b228def18fe94fed9ff8e588df006342210386543337772a9d5f9", sig: "6918d51c4bc72c29b400a257f21f4b7afa3053277e78c3047d6ed23ccba600cb0aaeee88aac402cfd385dcc0dde85f8ad3741c0fcf3eb8e0e1029cc713a9d37b", message: "3359345a31594c7856766b444e4c4b5831633542344b78475a4e484764504a71433757626657745a396a6165")
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainNavigationStack()
                .environmentObject(ApplicationState.shared) // Shared monolithic mutable state
        }
        .modelContainer(sharedModelContainer)
//        .onChange(of: scenePhase) { phase in
//            if phase == .inactive {
//                // TODO: Anything that needs doing on app backgrounded.
//            }
//        }
    }
}
