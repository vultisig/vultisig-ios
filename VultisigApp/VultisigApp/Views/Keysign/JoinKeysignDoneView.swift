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
    
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        view
            .redacted(reason: viewModel.txid.isEmpty ? .placeholder : [])
    }
    
    var view: some View {
        VStack(spacing: 32) {
            cards
            continueButton
        }
    }
    
    var cards: some View {
        JoinKeysignDoneSummary(viewModel: viewModel, showAlert: $showAlert)
    }

    var continueButton: some View {
        NavigationLink(destination: {
            HomeView(selectedVault: vault, showVaultsList: false)
        }, label: {
            FilledButton(title: "complete")
        })
        .id(UUID())
        .padding(20)
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneView(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
}
