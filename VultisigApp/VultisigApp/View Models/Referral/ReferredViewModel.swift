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
    
    private let thorchainReferralService = THORChainAPIService()
    
    var title: String {
        savedReferredCode.isEmpty ? "addReferredCode" : "editReferredCode"
    }
    
    var referredTitleText: String {
        savedReferredCode.isEmpty ? "addYourFriendsCode" : "changeFriendsReferralCode"
    }
    
    func closeBannerSheet() {
        showReferralBannerSheet = false
        navigationToReferralOverview = true
    }
    
    func showReferralDashboard() {
        navigationToReferralOverview = false
        navigationToReferralsView = true
        showReferralCodeOnboarding = false
    }
    
    func verifyReferredCode(savedGeneratedReferralCode: String) async -> Bool {
        resetReferredData()
        
        isLoading = true
        
        nameErrorCheck(code: referredCode, savedGeneratedReferralCode: savedGeneratedReferralCode)
        
        guard !showReferredLaunchViewError else {
            return false
        }
        
        return await checkNameAvailability(code: referredCode)
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
    
    private func checkNameAvailability(code: String) async -> Bool {
        do {
            let thorname = try await thorchainReferralService.getThornameLookup(name: code)
            
            let hasThorAlias = thorname.entries.contains {
                $0.chain == "THOR" &&  $0.address == thorname.owner
            }
            
            guard hasThorAlias else {
                showNameError(with: "referralCodeWithoutAlias")
                return false
            }
            
            saveReferredCode()
            return true
        } catch {
            let errorMessage = (error as? THORChainAPIError) == THORChainAPIError.thornameNotFound ? "referralCodeNotFound" : "systemErrorMessage"
            showNameError(with: errorMessage)
            return false
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
