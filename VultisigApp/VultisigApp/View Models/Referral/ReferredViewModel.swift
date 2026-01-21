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

    @Published var isLoading: Bool = false

    @Published var referredCode: String = ""
    @Published var showReferredLaunchViewSuccess: Bool = false
    @Published var referredLaunchViewErrorMessage: String?
    @Published var referredLaunchViewSuccessMessage: String = ""

    private let thorchainReferralService = THORChainAPIService()
    @Published var currentVault: Vault?

    var title: String {
        hasReferredCode ? "editFriendsReferral" : "addFriendsReferral"
    }

    var referredButtonDisabled: Bool {
        savedReferredCode == referredCode.uppercased()
    }

    var referredButtonTitle: String {
        hasReferredCode ? "editReferredCode" : "saveReferredCode"
    }

    var savedReferredCode: String {
        currentVault?.referredCode?.code ?? .empty
    }

    var hasReferredCode: Bool {
        savedReferredCode.isNotEmpty
    }

    func setData() {
        currentVault = AppViewModel.shared.selectedVault
        referredCode = savedReferredCode
    }

    func verifyAndSaveReferredCode() async -> Bool {
        let verified = await verifyReferredCode()

        if verified {
            saveReferredCode()
        }

        return verified
    }

    func verifyReferredCode() async -> Bool {
        clearFormMessages()

        // If code is empty, it acts like removing the referred code
        guard !referredCode.isEmpty else {
            saveReferredCode()
            return true
        }

        isLoading = true

        nameErrorCheck(code: referredCode, referralCode: currentVault?.referralCode?.code)

        guard referredLaunchViewErrorMessage == nil else {
            return false
        }

        do {
            try await ReferredCodeInteractor().verify(code: referredCode)
            return true
        } catch {
            showNameError(with: error.localizedDescription)
            return false
        }
    }

    func clearFormMessages() {
        showReferredLaunchViewSuccess = false
        referredLaunchViewErrorMessage = nil
        referredLaunchViewSuccessMessage = ""
    }

    func resetData() {
        referredCode = ""
        clearFormMessages()
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

    private func showNameError(with message: String) {
        referredLaunchViewErrorMessage = message.localized
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

struct ReferredCodeInteractor {
    private let thorchainReferralService = THORChainAPIService()

    func verify(code: String) async throws {
        do {
            let thorname = try await thorchainReferralService.getThornameLookup(name: code)

            let hasThorAlias = thorname.entries.contains {
                $0.chain == "THOR" &&  $0.address == thorname.owner
            }

            guard hasThorAlias else {
                throw HelperError.runtimeError("referralCodeWithoutAlias")
            }
        } catch {
            let errorMessage = (error as? THORChainAPIError) == THORChainAPIError.thornameNotFound ? "referralCodeNotFound" : "systemErrorMessage"
            throw HelperError.runtimeError(errorMessage)
        }
    }
}
