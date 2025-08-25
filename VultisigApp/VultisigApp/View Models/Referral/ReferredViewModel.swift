//
//  ReferredViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI
import SwiftData

@MainActor
class ReferredViewModel: ObservableObject {
    @AppStorage("showReferralCodeOnboarding") var showReferralCodeOnboarding: Bool = true
    @Published var showReferralBannerSheet: Bool = false
    @Published var navigationToReferralOverview: Bool = false
    @Published var navigationToReferralsView: Bool = false
    
    @Published var isLoading: Bool = false
    
    @Published var referredCode: String = ""
    @Published var showReferredLaunchViewError: Bool = false
    @Published var showReferredLaunchViewSuccess: Bool = false
    @Published var referredLaunchViewErrorMessage: String = ""
    @Published var referredLaunchViewSuccessMessage: String = ""
    
    private let thorchainReferralService = THORChainAPIService()
    var currentVault: Vault? {
        ApplicationState.shared.currentVault
    }
    
    var title: String {
        hasReferredCode ? "editFriendsReferral" : "addFriendsReferral"
    }
    
    var savedReferredCode: String {
        currentVault?.referredCode?.code ?? .empty
    }
    
    var hasReferredCode: Bool {
        savedReferredCode.isNotEmpty
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
    
    func verifyReferredCode() async -> Bool {
        resetReferredData()
        
        isLoading = true
        
        nameErrorCheck(code: referredCode, referralCode: currentVault?.referralCode?.code)
        
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
        guard let currentVault = currentVault else {
            showNameError(with: "systemErrorMessage")
            return
        }
        
        saveReferredCode(code: referredCode, vault: currentVault)
        
        isLoading = false
    }
    
    func saveReferredCode(code: String, vault: Vault) {
        let normalized = code.uppercased()
        if let existing = vault.referredCode {
            existing.code = normalized
        } else {
            let model = ReferredCode(code: normalized, vault: vault)
            vault.referredCode = model
            Storage.shared.insert(model)
        }
        do {
            try Storage.shared.save()
            referredLaunchViewSuccessMessage = "referralCodeAdded"
            showReferredLaunchViewSuccess = true
        } catch {
            showNameError(with: "systemErrorMessage")
        }
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
    
    private func nameErrorCheck(code: String, referralCode: String?) {
        guard !code.isEmpty else {
            showNameError(with: "emptyField")
            return
        }
        
        guard code != referralCode else {
            showNameError(with: "referralCodeMatch")
            return
        }
        
        guard code.count <= 4 else {
            showNameError(with: "referralLaunchCodeLengthError")
            return
        }
    }
    
    // TODO: - Remove after release
    func migrateCodeIfNeeded() {
        guard
            let savedReferredCode = UserDefaults.standard.string(forKey: "savedReferredCode"),
            savedReferredCode.isNotEmpty,
            let currentVault
        else { return }
        
        saveReferredCode(code: savedReferredCode, vault: currentVault)
        UserDefaults.standard.setValue(nil, forKey: "savedReferredCode")
    }
}
