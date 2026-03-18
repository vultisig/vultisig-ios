//
//  JoinKeysignDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct JoinKeysignDoneView: View {
    let vault: Vault
    @ObservedObject var viewModel: KeysignViewModel
    @Binding var showAlert: Bool

    var body: some View {
        VStack(spacing: 32) {
            JoinKeysignDoneSummary(
                vault: vault,
                viewModel: viewModel,
                showAlert: $showAlert
            )
        }
        .redacted(reason: viewModel.showRedacted ? .placeholder : [])
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneView(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
    .environmentObject(AppViewModel())
}

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
