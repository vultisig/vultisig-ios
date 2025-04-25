//
//  JoinSwapDoneSummary+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-24.
//

#if os(macOS)
import SwiftUI
import Cocoa

extension JoinSwapDoneSummary {
    func copyHash(_ txid: String?) {
        guard let txid else {
            return
        }
        
        let urlStr = keysignViewModel.getTransactionExplorerURL(txid: txid)
        showAlert = true

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlStr, forType: .string)
    }
}
#endif
