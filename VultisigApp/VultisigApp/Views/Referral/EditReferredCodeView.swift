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
    
    var body: some View {
        ZStack {
            Background()
            container
            
            if referredViewModel.isLoading {
                loader
            }
        }
        .onAppear {
            setData()
        }
        .onDisappear {
            resetData()
        }
    }
    
    var content: some View {
        VStack {
            main
            button
        }
    }
    
    var main: some View {
        ScrollView {
            VStack(spacing: 8) {
                title
                textField
            }
        }
        .foregroundColor(.neutral0)
        .padding(24)
    }
    
    var title: some View {
        Text(NSLocalizedString("useReferralCode", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
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
        Button {
            referredViewModel.verifyReferredCode(savedGeneratedReferralCode: referralViewModel.savedGeneratedReferralCode)
        } label: {
            FilledButton(title: "saveReferredCode", textColor: .neutral0, background: .persianBlue400)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
