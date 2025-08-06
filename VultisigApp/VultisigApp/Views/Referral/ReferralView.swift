//
//  ReferralView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-07.
//

import SwiftUI

struct ReferralView: View {
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var referralViewModel = ReferralViewModel()
    
    var body: some View {
        ZStack {
            if referredViewModel.showReferralCodeOnboarding {
                referralCodeButton
            } else {
                referralCodeNavigationLink
            }
        }
        .navigationDestination(isPresented: $referredViewModel.navigationToReferralOverview) {
            ReferredOnboardingView(referredViewModel: referredViewModel)
        }
        .navigationDestination(isPresented: $referredViewModel.navigationToReferralsView) {
            referralView
        }
        .sheet(isPresented: $referredViewModel.showReferralBannerSheet) {
            referralOverviewSheet
        }
    }
    
    var referralCodeNavigationLink: some View {
        NavigationLink {
            referralView
        } label: {
            referralCodeLabel
        }
    }
    
    var referralCodeButton: some View {
        Button {
            referredViewModel.showReferralBannerSheet = true
        } label: {
            referralCodeLabel
        }
    }
    
    var referralCodeLabel: some View {
        SettingCell(title: "referralCode", icon: "horn")
    }
    
    var referralOverviewSheet: some View {
        ReferralOnboardingBanner(referredViewModel: referredViewModel)
            .presentationDetents([.height(400)])
    }
    
    @ViewBuilder
    var referralView: some View {
        if referralViewModel.hasReferralCode {
            ReferralMainScreen(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        } else {
            ReferralLaunchView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        }
    }
}

#Preview {
    ReferralView()
}
