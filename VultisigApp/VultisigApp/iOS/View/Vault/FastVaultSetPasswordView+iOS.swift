//
//  FastVaultSetPasswordView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension FastVaultSetPasswordView {

    var content: some View {
        ZStack {
            Background()
            main

            if isLoading {
                Loader()
            }
        }
        .navigationTitle(NSLocalizedString("", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var main: some View {
        view
            .navigationDestination(isPresented: $isLinkActive) {
                FastVaultSetHintView(tssType: tssType, vault: vault, selectedTab: selectedTab, fastVaultEmail: fastVaultEmail, fastVaultPassword: password, fastVaultExist: fastVaultExist)
            }
    }
    
    var view: some View {
        VStack {
            passwordField
            Spacer()
            button
        }
    }
}
#endif
