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
    
    @State var moveToHome: Bool = false
    
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        view
            .redacted(reason: viewModel.txid.isEmpty ? .placeholder : [])
            .navigationDestination(isPresented: $moveToHome) {
                HomeView(selectedVault: vault, showVaultsList: false)
            }
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
        Button {
            handleTap()
        } label: {
            FilledButton(title: "complete")
        }
        .id(UUID())
        .padding(20)
    }
    
    private func handleTap() {
        moveToHome = true
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneView(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
}
