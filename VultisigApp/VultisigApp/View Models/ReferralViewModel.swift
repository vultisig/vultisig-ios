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
    @Published var showReferredLaunchViewError: Bool = false
    @Published var showReferredLaunchViewSuccess: Bool = false
    @Published var referredLaunchViewErrorMessage: String = ""
    @Published var referredLaunchViewSuccessMessage: String = ""
    
    // Generated Referral Code
    @AppStorage("savedGeneratedReferralCode") var savedGeneratedReferralCode: String = ""
    @Published var referralCode: String = ""
    @Published var showReferralAvailabilityError: Bool = false
    @Published var referralAvailabilityErrorMessage: String = ""
    @Published var showReferralAvailabilitySuccess: Bool = false
    @Published var isReferralCodeVerified: Bool = false
    @Published var expireInCount: Int = 0
    
    @Published var showReferralAlert = false
    @Published var referralAlertMessage = ""
    @Published var navigateToOverviewView = false
    
    var registrationFee: String {
        getFiatAmount(for: 10)
    }
    
    var totalFee: String {
        getFiatAmount(for: getTotalFee())
    }
    
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
        resetReferredData()
        
        isLoading = true
        
        nameErrorCheck(code: referredCode, forReferralCode: false)
        
        guard !showReferredLaunchViewError else {
            return
        }
        
        Task {
            await checkNameAvailability(code: referredCode, forReferralCode: false)
        }
    }
    
    func verifyReferralCode() {
        isLoading = true
        resetReferralData()
        nameErrorCheck(code: referralCode, forReferralCode: true)
        
        guard !showReferralAvailabilityError else {
            return
        }
        
        Task {
            await checkNameAvailability(code: referralCode, forReferralCode: true)
        }
    }
    
    func resetReferredData() {
        showReferredLaunchViewError = false
        showReferredLaunchViewSuccess = false
        referredLaunchViewErrorMessage = ""
        referredLaunchViewSuccessMessage = ""
    }
    
    func handleCounterIncrease() {
        expireInCount += 1
    }
    
    func handleCounterDecrease() {
        guard expireInCount > 0 else {
            return
        }
        
        expireInCount -= 1
    }
    
    func verifyReferralEntries() {
        guard isReferralCodeVerified else {
            showAlert(with: "pickValidCode")
            return
        }
        
        guard expireInCount>0 else {
            showAlert(with: "pickValidExpiration")
            return
        }
        
        navigateToOverviewView = true
    }
    
    func getTotalFee() -> Int {
        10 + expireInCount
    }
    
    func getFiatAmount(for amount: Int) -> String {
        guard let nativeCoin = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) else {
            return ""
        }
        
        let fiatAmount = RateProvider.shared.fiatBalance(value: Decimal(amount), coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    private func showAlert(with message: String) {
        referralAlertMessage = message
        showReferralAlert = true
    }
    
    private func checkNameAvailability(code: String, forReferralCode: Bool) async {
        let urlString = Endpoint.checkNameAvailability(for: code)
        guard let url = URL(string: urlString) else {
            showNameError(forReferralCode: forReferralCode, with: "systemErrorMessage")
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if forReferralCode {
                        showNameError(forReferralCode: forReferralCode, with: "alreadyTaken")
                    } else {
                        saveReferredCode()
                    }
                } else if httpResponse.statusCode == 404 {
                    if forReferralCode {
                        saveReferralCode()
                    } else {
                        showNameError(forReferralCode: forReferralCode, with: "referralCodeNotFound")
                    }
                } else {
                    showNameError(forReferralCode: forReferralCode, with: "systemErrorMessage")
                }
            }
        } catch {
            showNameError(forReferralCode: forReferralCode, with: "systemErrorMessage")
        }
    }
    
    private func saveReferredCode() {
        savedReferredCode = referredCode
        referredLaunchViewSuccessMessage = "referralCodeAdded"
        showReferredLaunchViewSuccess = true
        isLoading = false
    }
    
    private func saveReferralCode() {
        isReferralCodeVerified = true
        showReferralAvailabilitySuccess = true
        isLoading = false
        isReferralCodeVerified = true
    }
    
    private func resetReferralData() {
        showReferralAvailabilityError = false
        referralAvailabilityErrorMessage = ""
        showReferralAvailabilitySuccess = false
        isReferralCodeVerified = false
    }
    
    private func nameErrorCheck(code: String, forReferralCode: Bool) {
        guard !code.isEmpty else {
            showNameError(forReferralCode: forReferralCode, with: "emptyField")
            return
        }
        
        guard !containsWhitespace(code) else {
            showNameError(forReferralCode: forReferralCode, with: "whitespaceNotAllowed")
            return
        }
        
        if !forReferralCode {
            guard code != savedGeneratedReferralCode else {
                showNameError(forReferralCode: forReferralCode, with: "referralCodeMatch")
                return
            }
        }
        
        guard code.count == 4 else {
            showNameError(forReferralCode: forReferralCode, with: "referralLaunchCodeLengthError")
            return
        }
    }
    
    private func showNameError(forReferralCode: Bool, with message: String) {
        if forReferralCode {
            if message == "alreadyTaken" {
                referralAvailabilityErrorMessage = message
            } else {
                referralAvailabilityErrorMessage = "invalid"
            }
            showReferralAvailabilityError = true
        } else {
            referredLaunchViewErrorMessage = message
            showReferredLaunchViewError = true
        }
        isLoading = false
    }
    
    private func containsWhitespace(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }
}
