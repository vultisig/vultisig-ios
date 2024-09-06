//
//  JoinKeysignDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import SwiftUI

extension JoinKeysignDoneView {
    func copyHash(txid: String) {
        let urlStr = viewModel.getTransactionExplorerURL(txid: txid)
        showAlert = true
    }
}
#endif
