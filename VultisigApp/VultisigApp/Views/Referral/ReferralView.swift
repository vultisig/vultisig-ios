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
        .navigationDestination(isPresented: $referredViewModel.navigationToReferralOverview, destination: {
            ReferredOnboardingView(referredViewModel: referredViewModel)
        })
        .navigationDestination(isPresented: $referredViewModel.navigationToCreateReferralView, destination: {
            ReferralLaunchView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        })
        .sheet(isPresented: $referredViewModel.showReferralBannerSheet) {
            referralOverviewSheet
        }
    }
    
    var referralCodeNavigationLink: some View {
        NavigationLink {
            ReferralLaunchView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
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
}

#Preview {
    ReferralView()
}
