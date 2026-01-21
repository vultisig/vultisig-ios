//
//  JoinKeysignDoneView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(iOS)
import SwiftUI

extension JoinKeysignDoneSummary {
    func copyHash(txid: String) {
        let urlStr = viewModel.getTransactionExplorerURL(txid: txid)
        showAlert = true

        let pasteboard = UIPasteboard.general
        pasteboard.string = urlStr
    }
}
#endif
