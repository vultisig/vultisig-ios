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
        container
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
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    var main: some View {
        VStack {
            ScrollView {
                ReferredOnboardingGuideAnimation()
                    .padding(.horizontal, 24)
            }
            
            button
        }
        .padding(.horizontal, -24)
    }
}

#Preview {
    ReferredOnboardingView(referredViewModel: ReferredViewModel())
}
