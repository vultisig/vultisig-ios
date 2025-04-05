//
//  SendCryptoDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
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
            showAlert = true
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(explorerLink, forType: .string)
        }
    }
}
#endif
