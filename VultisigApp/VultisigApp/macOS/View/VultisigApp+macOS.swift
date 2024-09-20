//
//  VultisigApp+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension VultisigApp {
    var content: some Scene {
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
                .environmentObject(macCheckUpdateViewModel)
                .environmentObject(macCameraServiceViewModel)
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
        }
        .modelContainer(sharedModelContainer)
    }
}
#endif
