//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI

@MainActor
class ReferralViewModel: ObservableObject {
    @AppStorage("showReferralCodeOnboarding") var showReferralCodeOnboarding: Bool = true
    @Published var showReferralBannerSheet: Bool = false
    @Published var navigationToReferralOverview: Bool = false
    @Published var navigationToCreateReferralView: Bool = false
    
    @Published var isLoading: Bool = false
    
    // Referred Code
    @AppStorage("savedReferredCode") var savedReferredCode: String = ""
    @Published var referredCode: String = ""
    @Published var showReferralLaunchViewError: Bool = false
    @Published var showReferralLaunchViewSuccess: Bool = false
    @Published var referralLaunchViewErrorMessage: String = ""
    @Published var referralLaunchViewSuccessMessage: String = ""
    
    // Generated Referral Code
    @AppStorage("savedGeneratedReferralCode") var savedGeneratedReferralCode: String = ""
    @Published var referralCode: String = ""
    
    func closeBannerSheet() {
        showReferralBannerSheet = false
        navigationToReferralOverview = true
    }
    
    func showReferralDashboard() {
        navigationToReferralOverview = false
        navigationToCreateReferralView = true
        showReferralCodeOnboarding = false
    }
    
    func verifyReferredCode() {
        resetReferralData()
        
        isLoading = true
        
        guard !referredCode.isEmpty else {
            referralLaunchViewErrorMessage = "emptyField"
            showReferralLaunchViewError = true
            isLoading = false
            return
        }
        
        guard referredCode != savedGeneratedReferralCode else {
            referralLaunchViewErrorMessage = "referralCodeMatch"
            showReferralLaunchViewError = true
            isLoading = false
            return
        }
        
        guard referredCode.count == 4 else {
            referralLaunchViewErrorMessage = "referralLaunchCodeLengthError"
            showReferralLaunchViewError = true
            isLoading = false
            return
        }
        
        Task {
            await checkNameAvailability()
        }
    }
    
    private func checkNameAvailability() async {
        let urlString = Endpoint.checkNameAvailability(for: referredCode)
        guard let url = URL(string: urlString) else {
            referralLaunchViewErrorMessage = "systemErrorMessage"
            showReferralLaunchViewError = true
            isLoading = false
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    saveReferredCode()
                } else if httpResponse.statusCode == 404 {
                    referralLaunchViewErrorMessage = "referralCodeNotFound"
                    showReferralLaunchViewError = true
                    isLoading = false
                } else {
                    referralLaunchViewErrorMessage = "systemErrorMessage"
                    showReferralLaunchViewError = true
                    isLoading = false
                }
            }
        } catch {
            referralLaunchViewErrorMessage = "systemErrorMessage"
            showReferralLaunchViewError = true
            isLoading = false
        }
    }
    
    func saveReferredCode() {
        savedReferredCode = referredCode
        referralLaunchViewSuccessMessage = "referralCodeAdded"
        showReferralLaunchViewSuccess = true
        isLoading = false
    }
    
    func resetReferralData() {
        showReferralLaunchViewError = false
        showReferralLaunchViewSuccess = false
        referralLaunchViewErrorMessage = ""
        referralLaunchViewSuccessMessage = ""
    }
}
