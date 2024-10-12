//
//  VaultDetailScanButton+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension VaultDetailScanButton {
    var content: some View {
        NavigationLink {
            MacScannerView(vault: vault, type: .SignTransaction, sendTx: sendTx)
        } label: {
            label
        }
    }
}
#endif
