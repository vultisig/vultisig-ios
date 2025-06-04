//
//  ReferralOnboardingBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferralOnboardingBanner: View {
    @ObservedObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        ZStack {
            Background()
            content
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
        Button {
            handleTap()
        } label: {
            label
        }
        .buttonStyle(.plain)
    }
    
    var label: some View {
        FilledButton(title: "next")
            .padding(.bottom, 24)
            .padding(.top, 12)
    }
    
    private func handleTap() {
        referralViewModel.closeBannerSheet()
    }
}

#Preview {
    ReferralOnboardingBanner(referralViewModel: ReferralViewModel())
}
