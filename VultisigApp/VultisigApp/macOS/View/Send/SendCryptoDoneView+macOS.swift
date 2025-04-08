//
//  SendCryptoDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SendCryptoDoneView {
    func copyHash(hash: String) {
        let explorerLink = explorerLink(hash: hash)
        if !explorerLink.isEmpty {
            alertTitle = "urlCopied"
            showAlert = true
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(explorerLink, forType: .string)
        }
    }
}
#endif
