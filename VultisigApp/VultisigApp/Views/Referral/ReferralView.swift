//
//  ReferralView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-07.
//

import SwiftUI

struct ReferralView: View {
    @StateObject var referralViewModel = ReferralViewModel()
    
    var body: some View {
        ZStack {
            if referralViewModel.showReferralCodeOnboarding {
                referralCodeButton
            } else {
                referralCodeNavigationLink
            }
        }
        .navigationDestination(isPresented: $referralViewModel.navigationToReferralOverview, destination: {
            ReferralOnboardingView(referralViewModel: referralViewModel)
        })
        .navigationDestination(isPresented: $referralViewModel.navigationToCreateReferralView, destination: {
            ReferralLaunchView(referralViewModel: referralViewModel)
        })
        .sheet(isPresented: $referralViewModel.showReferralBannerSheet) {
            referralOverviewSheet
        }
    }
    
    var referralCodeNavigationLink: some View {
        NavigationLink {
            ReferralLaunchView(referralViewModel: referralViewModel)
        } label: {
            referralCodeLabel
        }
    }
    
    var referralCodeButton: some View {
        Button {
            referralViewModel.showReferralBannerSheet = true
        } label: {
            referralCodeLabel
        }
    }
    
    var referralCodeLabel: some View {
        SettingCell(title: "referralCode", icon: "horn")
    }
    
    var referralOverviewSheet: some View {
        ReferralOnboardingBanner(referralViewModel: referralViewModel)
            .presentationDetents([.height(400)])
    }
}

#Preview {
    ReferralView()
}
