//
//  ReferredViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI

@MainActor
class ReferredViewModel: ObservableObject {
    @AppStorage("showReferralCodeOnboarding") var showReferralCodeOnboarding: Bool = true
    @Published var showReferralBannerSheet: Bool = false
    @Published var navigationToReferralOverview: Bool = false
    @Published var navigationToReferralsView: Bool = false
    
    @Published var isLoading: Bool = false
    
    // Referred Code
    @AppStorage("savedReferredCode") var savedReferredCode: String = ""
    @Published var referredCode: String = ""
    @Published var showReferredLaunchViewError: Bool = false
    @Published var showReferredLaunchViewSuccess: Bool = false
    @Published var referredLaunchViewErrorMessage: String = ""
    @Published var referredLaunchViewSuccessMessage: String = ""
    
    @AppStorage("savedGeneratedReferralCode") var savedGeneratedReferralCode: String = ""
    
    func closeBannerSheet() {
        showReferralBannerSheet = false
        navigationToReferralOverview = true
    }
    
    func showReferralDashboard() {
        navigationToReferralOverview = false
        navigationToReferralsView = true
        showReferralCodeOnboarding = false
    }
    
    func verifyReferredCode(savedGeneratedReferralCode: String) {
        resetReferredData()
        
        isLoading = true
        
        nameErrorCheck(code: referredCode, savedGeneratedReferralCode: savedGeneratedReferralCode)
        
        guard !showReferredLaunchViewError else {
            return
        }
        
        Task {
            await checkNameAvailability(code: referredCode)
        }
    }
    
    func resetReferredData() {
        showReferredLaunchViewError = false
        showReferredLaunchViewSuccess = false
        referredLaunchViewErrorMessage = ""
        referredLaunchViewSuccessMessage = ""
    }
    
    private func saveReferredCode() {
        savedReferredCode = referredCode
        referredLaunchViewSuccessMessage = "referralCodeAdded"
        showReferredLaunchViewSuccess = true
        isLoading = false
    }
    
    private func checkNameAvailability(code: String) async {
        let urlString = Endpoint.nameLookup(for: code)
        guard let url = URL(string: urlString) else {
            showNameError(with: "systemErrorMessage")
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    saveReferredCode()
                } else if httpResponse.statusCode == 404 {
                    showNameError(with: "referralCodeNotFound")
                } else {
                    showNameError(with: "systemErrorMessage")
                }
            }
        } catch {
            showNameError(with: "systemErrorMessage")
        }
    }
    
    private func showNameError(with message: String) {
        referredLaunchViewErrorMessage = message
        showReferredLaunchViewError = true
        isLoading = false
    }
    
    private func nameErrorCheck(code: String, savedGeneratedReferralCode: String) {
        guard !code.isEmpty else {
            showNameError(with: "emptyField")
            return
        }
        
        guard code != savedGeneratedReferralCode else {
            showNameError(with: "referralCodeMatch")
            return
        }
        
        guard code.count <= 4 else {
            showNameError(with: "referralLaunchCodeLengthError")
            return
        }
    }
}
