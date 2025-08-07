//
//  EditReferredCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct EditReferredCodeView: View {
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
                title
                textField
            }
        }
        .foregroundColor(Theme.colors.textPrimary)
    }
    
    var title: some View {
        Text(NSLocalizedString("useReferralCode", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
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
        PrimaryButton(title: "saveReferredCode") {
            Task { @MainActor in
                let codeUpdated = await referredViewModel.verifyReferredCode(savedGeneratedReferralCode: referralViewModel.savedGeneratedReferralCode)
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
        referredViewModel.referredCode = referredViewModel.savedReferredCode
    }
    
    private func resetData() {
        referredViewModel.resetReferredData()
    }
}

#Preview {
    EditReferredCodeView(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
