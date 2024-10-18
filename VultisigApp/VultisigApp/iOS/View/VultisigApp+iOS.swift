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
        ContentView()
            .environmentObject(applicationState) // Shared monolithic mutable state
            .environmentObject(vaultDetailViewModel)
            .environmentObject(coinSelectionViewModel)
            .environmentObject(accountViewModel)
            .environmentObject(deeplinkViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(homeViewModel)
            .environmentObject(vultExtensionViewModel)
            .environmentObject(settingsDefaultChainViewModel)
            .environmentObject(phoneCheckUpdateViewModel)
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
            .onAppear() {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    continueLogin()
                }
            }
    }
}
#endif
