//
//  ReferredOnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferredOnboardingView: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    
    var body: some View {
        Screen(title: "referral".localized) {
            content
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
        PrimaryButton(title: "getStarted") {
            referredViewModel.showReferralDashboard()
        }
    }
    
    var main: some View {
        VStack {
            ScrollView {
                ReferredOnboardingGuideAnimation()
            }
            
            button
        }
    }
}

#Preview {
    ReferredOnboardingView(referredViewModel: ReferredViewModel())
}
