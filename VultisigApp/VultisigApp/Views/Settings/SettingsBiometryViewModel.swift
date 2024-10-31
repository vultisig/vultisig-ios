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
    @Published var isWrongPassword: Bool = false

    private var initialPassword: String = .empty
    private var initialHint: String = .empty

    private let keychain = DefaultKeychainService.shared
    private let fastVaultService = FastVaultService.shared

    func setData(vault: Vault) {
        if let password = keychain.getFastPassword(pubKeyECDSA: vault.pubKeyECDSA) {
            self.password = password
            self.initialPassword = password
        }
        if let hint = keychain.getFastHint(pubKeyECDSA: vault.pubKeyECDSA) {
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
        return (password != initialPassword && !password.isEmpty) || hint != initialHint
    }

    @MainActor func validateForm(vault: Vault) async -> Bool {
        if initialPassword != password {
            isLoading = true
            let isValid = await fastVaultService.get(
                pubKeyECDSA:  vault.pubKeyECDSA,
                password: password
            )
            isLoading = false

            guard isValid else {
                isWrongPassword = true
                return false
            }

            keychain.setFastPassword(
                password.isEmpty ? nil : password,
                pubKeyECDSA: vault.pubKeyECDSA
            )
        }

        if initialHint != hint {
            keychain.setFastHint(
                hint.isEmpty ? nil : hint,
                pubKeyECDSA: vault.pubKeyECDSA
            )
        }

        return true
    }
}
