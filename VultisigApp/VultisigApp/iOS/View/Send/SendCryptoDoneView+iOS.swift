//
//  SendCryptoDoneView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendCryptoDoneView {
    func copyHash(hash: String) {
        let explorerLink = explorerLink(hash: hash)
        if !explorerLink.isEmpty {
            alertTitle = "hashCopied"
            showAlert = true
            let pasteboard = UIPasteboard.general
            pasteboard.string = explorerLink
        }
    }
}
#endif
