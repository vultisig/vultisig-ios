//
//  ReferredCodeFormScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct ReferredCodeFormScreen: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    @ObservedObject var referralViewModel: ReferralViewModel
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Screen(title: referredViewModel.title.localized) {
            VStack {
                main
                button
            }
        }
        .overlay(referredViewModel.isLoading ? loader : nil)
        .onAppear {
            setData()
        }
        .onDisappear {
            resetData()
        }
    }
    
    var main: some View {
        ScrollView {
            VStack(spacing: 8) {
                HighlightedText(
                    localisedKey: "referredSaveOnSwaps",
                    highlightedText: "10%"
                ) {
                    $0.font = Theme.fonts.bodySMedium
                    $0.foregroundColor = Theme.colors.textPrimary
                } highlightedTextStyle: {
                    $0.foregroundColor = Theme.colors.primaryAccent4
                }
                .showIf(!referredViewModel.hasReferredCode)
                textField
            }
        }
        .foregroundColor(Theme.colors.textPrimary)
    }
    
    var textField: some View {
        ReferralTextField(
            text: $referredViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referredViewModel.showReferredLaunchViewError,
            errorMessage: referredViewModel.referredLaunchViewErrorMessage
        )
    }
    
    var button: some View {
        PrimaryButton(title: "saveReferral") {
            Task { @MainActor in
                let codeUpdated = await referredViewModel.verifyReferredCode()
                if codeUpdated {
                    dismiss()
                }
            }
            
        }
    }
    
    var loader: some View {
        Loader()
    }
    
    private func setData() {
        resetData()
        if referredViewModel.hasReferredCode {
            referredViewModel.referredCode = referredViewModel.savedReferredCode
        }
    }
    
    private func resetData() {
        referredViewModel.resetReferredData()
    }
}

#Preview {
    ReferredCodeFormScreen(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
