//
//  JoinKeysignDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import SwiftUI
import Cocoa

extension JoinKeysignDoneSummary {
    func copyHash(txid: String) {
        let urlStr = viewModel.getTransactionExplorerURL(txid: txid)
        showAlert = true

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlStr, forType: .string)
    }
}
#endif
