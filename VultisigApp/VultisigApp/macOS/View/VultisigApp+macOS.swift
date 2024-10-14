//
//  VultisigApp+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension VultisigApp {
    var content: some View {
        ContentView()
            .environmentObject(applicationState) // Shared monolithic mutable state
            .environmentObject(vaultDetailViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(accountViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(homeViewModel)
            .environmentObject(settingsDefaultChainViewModel)
            .environmentObject(vultExtensionViewModel)
            .environmentObject(macCheckUpdateViewModel)
            .environmentObject(macCameraServiceViewModel)
            .buttonStyle(BorderlessButtonStyle())
            .frame(minWidth: 900, minHeight: 600)
            .onAppear{
                NSWindow.allowsAutomaticWindowTabbing = false
                continueLogin()
            }
    }
}
#endif
