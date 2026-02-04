//
//  VultisigApp+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

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
            .environmentObject(coinService)
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
            .onAppear {
                // Run migrations on app launch
                AppMigrationService().performMigrationsIfNeeded()

                if ProcessInfo.processInfo.isiOSAppOnMac {
                    continueLogin()
                }
            }
    }
}
#endif
