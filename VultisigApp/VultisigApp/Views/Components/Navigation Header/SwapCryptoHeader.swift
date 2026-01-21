//
//  SwapCryptoHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct SwapCryptoHeader: View {
    let vault: Vault
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            content
            actions
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    var content: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction.opacity(0)
        }
    }

    var leadingAction: some View {
        backButton
    }

    var text: some View {
        Text(NSLocalizedString(swapViewModel.currentTitle, comment: "SendCryptoView title"))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }

    var trailingAction: some View {
        ZStack {
            NavigationQRShareButton(
                vault: vault,
                type: .Keysign,
                viewModel: shareSheetViewModel
            )
            .disabled(swapViewModel.currentIndex != 3)
        }
    }

    var backButton: some View {
        let isDone = swapViewModel.currentIndex==5

        return Button {
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }

    var refreshCounter: some View {
        SwapRefreshQuoteCounter(timer: swapViewModel.timer)
    }

    var actions: some View {
        HStack {
            Spacer()

            if swapViewModel.currentIndex>0 && swapViewModel.currentIndex<3 {
                refreshCounter
            } else if swapViewModel.currentIndex==3 {
                trailingAction
            }
        }
    }

    private func handleBackTap() {
        guard swapViewModel.currentIndex>1 else {
            dismiss()
            return
        }

        swapViewModel.handleBackTap()
    }
}

#Preview {
    SwapCryptoHeader(
        vault: Vault.example,
        swapViewModel: SwapCryptoViewModel(),
        shareSheetViewModel: ShareSheetViewModel()
    )
}
