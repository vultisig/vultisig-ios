//
//  ReferralOnboardingBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferralOnboardingBanner: View {
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
        Text(NSLocalizedString("referralOnboardingBannerTitle", comment: ""))
            .font(.body22BrockmannMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var description: some View {
        Text(NSLocalizedString("referralOnboardingBannerDescription", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
    }
    
    var button: some View {
        FilledButton(title: "next")
            .padding(.bottom, 24)
            .padding(.top, 12)
    }
}

#Preview {
    ReferralOnboardingBanner()
}
