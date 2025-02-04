//
//  FastVaultSetPasswordView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension FastVaultSetHintView {
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
            PeerDiscoveryView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastSignConfig: fastSignConfig)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "")
    }
    
    var view: some View {
        VStack {
            hintField
            Spacer()
            buttons
        }
        .padding(.horizontal, 25)
    }
}
#endif
