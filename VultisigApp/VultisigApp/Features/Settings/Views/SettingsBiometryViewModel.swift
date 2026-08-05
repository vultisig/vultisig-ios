//
//  SettingsBiometryViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.10.2024.
//

import Foundation
import SwiftUI

final class SettingsBiometryViewModel: ObservableObject {

    @AppStorage("isBiometryEnabled") var isBiometryEnabled: Bool = true

    @Published var password: String = .empty
    @Published var hint: String = .empty
    @Published var isLoading: Bool = false
    @Published var passwordError: String?

    private var initialPassword: String = .empty
    private var initialHint: String = .empty

    private let keychain = DefaultKeychainService.shared
    private let fastVaultService = FastVaultService.shared

    var saveHintEnabled: Bool {
        hint != initialHint
    }

    func resetData() {
        password = .empty
        passwordError = nil
    }

    func resetHintData(vault: Vault) {
        // The hint is a convenience the user can retype, so an unreadable
        // Keychain leaves the field exactly where a never-saved hint would.
        if let hint = keychain.getFastHint(pubKeyECDSA: vault.pubKeyECDSA).valueTreatingUnavailableAsAbsent {
           self.hint = hint
           self.initialHint = hint
       }
    }

    func onBiometryEnabledChanged(_ isOn: Bool, vault: Vault) {
        isBiometryEnabled = isOn

        if !isOn {
            keychain.setFastPassword(nil, pubKeyECDSA: vault.pubKeyECDSA)
            password = .empty
        }
    }

    var isSaveEnabled: Bool {
        return password.isNotEmpty && !isLoading
    }

    @MainActor func validateForm(vault: Vault) async -> Bool {
        isLoading = true
        let isValid = await fastVaultService.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: password
        )
        isLoading = false

        guard isValid else {
            passwordError = "wrongVaultPassword".localized
            return false
        }

        keychain.setFastPassword(
            password.isEmpty ? nil : password,
            pubKeyECDSA: vault.pubKeyECDSA
        )

        isBiometryEnabled = true
        return true
    }

    func saveHint(vault: Vault) {
        keychain.setFastHint(
            hint.isEmpty ? nil : hint,
            pubKeyECDSA: vault.pubKeyECDSA
        )
        initialHint = hint
    }
}
