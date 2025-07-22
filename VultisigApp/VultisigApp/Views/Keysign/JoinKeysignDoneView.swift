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
            
            if viewModel.keysignPayload?.swapPayload == nil {
                continueButton
            }
        }
    }
    
    var cards: some View {
        JoinKeysignDoneSummary(
            vault: vault,
            viewModel: viewModel,
            showAlert: $showAlert,
            moveToHome: $moveToHome
        )
    }

    var continueButton: some View {
        PrimaryButton(title: "done") {
            handleTap()
        }
        .id(UUID())
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
