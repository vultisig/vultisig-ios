//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI

class ReferralViewModel: ObservableObject {
    @AppStorage("showReferralCodeOnboarding") var showReferralCodeOnboarding: Bool = true
    @AppStorage("savedReferredCode") var savedReferredCode: Bool = true
    
    @Published var showReferralBannerSheet: Bool = false
    @Published var navigationToReferralOverview: Bool = false
    @Published var navigationToCreateReferralView: Bool = false
    
    // Referred Code
    @Published var referredCode: String = ""
    @Published var showReferralLaunchViewError: Bool = false
    @Published var referralLaunchViewErrorMessage: String = ""
    
    func closeBannerSheet() {
        showReferralBannerSheet = false
        navigationToReferralOverview = true
    }
    
    func showReferralDashboard() {
        navigationToReferralOverview = false
        navigationToCreateReferralView = true
        showReferralCodeOnboarding = false
    }
    
    func saveReferredCode() {
        showReferralLaunchViewError = false
        
        guard !referredCode.isEmpty else {
            referralLaunchViewErrorMessage = "emptyField"
            showReferralLaunchViewError = true
            return
        }
        
        guard referredCode.count == 4 else {
            referralLaunchViewErrorMessage = "referralLaunchCodeLengthError"
            showReferralLaunchViewError = true
            return
        }
        
        verifyReferredCode()
    }
    
    private func verifyReferredCode() {
        
    }
}
