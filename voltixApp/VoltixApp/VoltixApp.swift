//
//  VoltixApp.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/1/2024.
//

import SwiftUI
import SwiftData
import Mediator

@main
struct VoltixApp: App {
    @StateObject var appNavigationState = AppNavigationState()
    private static let mediator = Mediator.shared  // initialise web server
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
//            Item.self, // TODO: remove it later
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
            MainNavigationView()
        }
        .modelContainer(sharedModelContainer)
//        .onChange(of: scenePhase) { phase in
//            if phase == .inactive {
//                // TODO: Anything that needs doing on app backgrounded.
//            }
//        }
    }
}


// App Delegate
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Remove default black background from SwiftUI List backed UITableView
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        return true
    }
}
