//
//  EditReferredCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct EditReferredCodeView: View {
    @StateObject var referralViewModel: ReferredViewModel
    
    var body: some View {
        ZStack {
            Background()
            container
            
            if referralViewModel.isLoading {
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
            text: $referralViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referralViewModel.showReferredLaunchViewError,
            errorMessage: referralViewModel.referredLaunchViewErrorMessage
        )
    }
    
    var button: some View {
        Button {
            referralViewModel.verifyReferredCode()
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
        referralViewModel.referredCode = referralViewModel.savedReferredCode
    }
    
    private func resetData() {
        referralViewModel.resetReferredData()
    }
}

#Preview {
    EditReferredCodeView(referralViewModel: ReferredViewModel())
}
