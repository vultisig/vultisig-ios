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
    @AppStorage("savedReferredCode") var savedReferredCode: Bool = true
    
    @Published var showReferralBannerSheet: Bool = false
    @Published var navigationToReferralOverview: Bool = false
    @Published var navigationToCreateReferralView: Bool = false
    
    @Published var isLoading: Bool = false
    
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
    
    func verifyReferredCode() {
        showReferralLaunchViewError = false
        
        isLoading = true
        defer { isLoading = false }
        
        // Validate input
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
        
        Task {
            await checkNameAvailability()
        }
    }
    
    private func checkNameAvailability() async {
        let urlString = Endpoint.checkNameAvailability(for: referredCode)
        guard let url = URL(string: urlString) else {
            referralLaunchViewErrorMessage = "systemErrorMessage"
            showReferralLaunchViewError = true
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
                } else {
                    referralLaunchViewErrorMessage = "systemErrorMessage"
                    showReferralLaunchViewError = true
                }
            }
        } catch {
            referralLaunchViewErrorMessage = "systemErrorMessage"
            showReferralLaunchViewError = true
        }
    }
    
    func saveReferredCode() {
        
    }
}
