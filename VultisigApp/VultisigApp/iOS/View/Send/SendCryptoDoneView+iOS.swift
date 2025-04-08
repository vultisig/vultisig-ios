//
//  SendCryptoDoneView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendCryptoDoneView {
    var sendView: some View {
        VStack {
            cards
            continueButton
                .navigationDestination(isPresented: $navigateToHome) {
                    HomeView(selectedVault: vault)
                }
        }
    }
    
    func copyHash(hash: String) {
        let explorerLink = explorerLink(hash: hash)
        if !explorerLink.isEmpty {
            alertTitle = "urlCopied"
            showAlert = true
            let pasteboard = UIPasteboard.general
            pasteboard.string = explorerLink
        }
    }
}
#endif
