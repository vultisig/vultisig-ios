//
//  VoltixApp.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/1/2024.
//

import SwiftUI
import SwiftData

@main
struct VoltixApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self, // TODO: remove it later
            Vault.self,
            Coin.self,
            Chain.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
