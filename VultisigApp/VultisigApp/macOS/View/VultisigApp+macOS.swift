//
//  VultisigApp+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI
import UserNotifications

extension VultisigApp {
    var content: some View {
        ContentView(navigationRouter: navigationRouter)
            .environmentObject(applicationState) // Shared monolithic mutable state
            .environmentObject(vaultDetailViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(accountViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(homeViewModel)
            .environmentObject(vultExtensionViewModel)
            .environmentObject(phoneCheckUpdateViewModel)
            .environmentObject(globalStateViewModel)
            .environmentObject(sheetPresentedCounterManager)
            .buttonStyle(BorderlessButtonStyle())
            .frame(minWidth: 900, minHeight: 600)
            .onAppear{
                NSWindow.allowsAutomaticWindowTabbing = false
                continueLogin()
            }
    }
}
#endif
