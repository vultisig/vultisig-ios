//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-13.
//

import SwiftUI

@MainActor
class ReferralViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    
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
    
    // Fees
    @Published var registrationFee: Decimal = 0
    @Published var totalFee: Decimal = 0
    @Published var isFeesLoading: Bool = false
    
    // Send Overview
    @Published var isAmountCorrect: Bool = false
    @Published var isAddressCorrect: Bool = false
    @Published var showSendOverviewAlert = false
    @Published var navigateToSendView = false
    
    var registrationFeeFiat: String {
        getFiatAmount(for: getRegistrationFee())
    }
    
    var totalFeeFiat: String {
        getFiatAmount(for: getTotalFee())
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
    
    func getRegistrationFee() -> Decimal {
        registrationFee / 100_000_000
    }
    
    func getTotalFee() -> Decimal {
        Decimal(10 + expireInCount)
    }
    
    func getFiatAmount(for amount: Decimal) -> String {
        guard let nativeCoin = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) else {
            return ""
        }
        
        let fiatAmount = RateProvider.shared.fiatBalance(value: amount, coin: nativeCoin)
        return fiatAmount.formatToFiat(includeCurrencySymbol: true, useAbbreviation: true)
    }
    
    func verifySendOverviewDetails() {
        guard isAmountCorrect else {
            showSendOverviewAlert = true
            return
        }
        
        guard isAddressCorrect else {
            showSendOverviewAlert = true
            return
        }
        
        navigateToSendView = true
    }
    
    private func showAlert(with message: String) {
        referralAlertMessage = message
        showReferralAlert = true
    }
    
    private func showNameError(with message: String) {
        if message == "alreadyTaken" {
            referralAvailabilityErrorMessage = message
        } else {
            referralAvailabilityErrorMessage = "invalid"
        }
        
        showReferralAvailabilityError = true
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
            showNameError(with: "emptyField")
            return
        }
        
        guard !containsWhitespace(code) else {
            showNameError(forReferralCode: forReferralCode, with: "whitespaceNotAllowed")
            return
        }
        
        if !forReferralCode {
            guard code != savedGeneratedReferralCode else {
                showNameError(with: "referralCodeMatch")
                return
            }
        }
        
        guard code.count == 4 else {
            showNameError(with: "referralLaunchCodeLengthError")
            return
        }
    }
    
    private func checkNameAvailability(code: String, forReferralCode: Bool) async {
        let urlString = Endpoint.checkNameAvailability(for: code)
        guard let url = URL(string: urlString) else {
            showNameError(with: "systemErrorMessage")
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    showNameError(with: "alreadyTaken")
                } else if httpResponse.statusCode == 404 {
                    if forReferralCode {
                        saveReferralCode()
                    } else {
                        showNameError(with: "referralCodeNotFound")
                    }
                } else {
                    showNameError(with: "systemErrorMessage")
                }
            }
        } catch {
            showNameError(with: "systemErrorMessage")
        }
        isLoading = false
    }
    
    func calculateFees() async {
        isFeesLoading = true
        
        guard let url = URL(string: Endpoint.ReferralFees) else {
            print("Invalid URL")
            isFeesLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let info = try decoder.decode(ThorchainNetworkAllFees.self, from: data)
            registrationFee = Decimal(string: info.tns_register_fee_rune) ?? 0
            totalFee = Decimal(string: info.tns_fee_per_block_rune) ?? 0
            isFeesLoading = false
        } catch {
            print("Network or decoding error: \(error)")
            isFeesLoading = false
        }
    }
    
    private func containsWhitespace(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }

// Codable struct for all relevant fields from the endpoint
struct ThorchainNetworkAllFees: Codable {
    let tns_register_fee_rune: String
    let tns_fee_per_block_rune: String
}

}
