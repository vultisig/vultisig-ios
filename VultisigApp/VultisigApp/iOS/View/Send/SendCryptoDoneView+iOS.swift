//
//  SendCryptoDoneView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendCryptoDoneView {
    var view: some View {
        VStack {
            cards
            continueButton
        }
    }
    
    func copyHash(hash: String) {
        let explorerLink = explorerLink(hash: hash)
        if !explorerLink.isEmpty {
            showAlert = true
            let pasteboard = UIPasteboard.general
            pasteboard.string = explorerLink
        }
    }
}
#endif
