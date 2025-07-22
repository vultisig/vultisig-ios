//
//  ReferralOnboardingBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferralOnboardingBanner: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    
    var body: some View {
        ZStack {
            Background()
            content
            closeButtonContainer
        }
    }
    
    var content: some View {
        VStack(spacing: 12) {
            image
            Spacer()
            title
            button
        }
        .frame(height: 400)
        .padding(.horizontal, 24)
    }
    
    var image: some View {
        Image("ReferralOnboardingBanner")
            .resizable()
            .frame(width: 240, height: 194)
            .padding(.bottom, 12)
    }
    
    var title: some View {
        Group {
            Text(NSLocalizedString("referralOnboardingBannerTitle1", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("referralOnboardingBannerTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("referralOnboardingBannerTitle3", comment: ""))
                .foregroundColor(.neutral0)
        }
        .font(.body22BrockmannMedium)
        .multilineTextAlignment(.center)
    }
    
    var button: some View {
        PrimaryButton(title: "next") {
            handleTap()
        }
        .padding(.bottom, 24)
        .padding(.top, 12)
    }
    
    var closeButtonContainer: some View {
        HStack {
            Spacer()
            VStack {
                closeButton
                
                Spacer()
            }
        }
    }
    
    var closeButton: some View {
        Button {
            referredViewModel.showReferralBannerSheet = false
        } label: {
            closeLabel
        }
        .buttonStyle(.plain)
        .padding(24)
    }
    
    var closeLabel: some View {
        Image(systemName: "xmark")
            .font(.body22BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    private func handleTap() {
        referredViewModel.closeBannerSheet()
    }
}

#Preview {
    ReferralOnboardingBanner(referredViewModel: ReferredViewModel())
}
