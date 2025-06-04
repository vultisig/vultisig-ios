//
//  ReferralOnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferralOnboardingView: View {
    @ObservedObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        ZStack {
            Background()
            shadow
            main
        }
    }

    var main: some View {
        VStack {
            ReferralOnboardingGuideAnimation()
            Spacer()
            button
        }
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(.alertTurquoise)
            .opacity(0.05)
            .blur(radius: 20)
    }
    
    var button: some View {
        Button {
            referralViewModel.showReferralDashboard()
        } label: {
            label
        }
    }
    
    var label: some View {
        FilledButton(title: "getStarted")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
    }
}

#Preview {
    ReferralOnboardingView(referralViewModel: ReferralViewModel())
}
