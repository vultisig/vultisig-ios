//
//  FastVaultSetPasswordView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FastVaultSetPasswordView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
        .navigationDestination(isPresented: $isLinkActive) {
            PeerDiscoveryView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: fastVaultEmail, fastVaultPassword: password)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "password")
    }
    
    var view: some View {
        VStack {
            passwordField
            Spacer()
            disclaimer
            buttons
        }
        .padding(.horizontal, 25)
    }
}
#endif
