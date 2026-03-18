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
