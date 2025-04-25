//
//  JoinSwapDoneSummary+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-24.
//

#if os(iOS)
import SwiftUI

extension JoinSwapDoneSummary {
    func copyHash(_ txid: String?) {
        guard let txid else {
            return
        }
        
        let urlStr = keysignViewModel.getTransactionExplorerURL(txid: txid)
        showAlert = true
        
        let pasteboard = UIPasteboard.general
        pasteboard.string = urlStr
    }
}
#endif
