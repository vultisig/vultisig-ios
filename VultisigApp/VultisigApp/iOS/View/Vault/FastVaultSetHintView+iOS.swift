//
//  FastVaultSetPasswordView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FastVaultSetHintView {

    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
            .navigationDestination(isPresented: $isLinkActive) {
                PeerDiscoveryView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastSignConfig: fastSignConfig)
            }
    }
    
    var view: some View {
        VStack {
            hintField
            Spacer()
            buttons
        }
    }
}
#endif
