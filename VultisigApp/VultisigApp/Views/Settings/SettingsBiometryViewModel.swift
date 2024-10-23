//
//  SettingsBiometryViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.10.2024.
//

import Foundation
import SwiftUI

final class SettingsBiometryViewModel: ObservableObject {

    @AppStorage("isBiometryEnabled") var isBiometryEnabled: Bool = false

    @Published var password: String = .empty
    @Published var isLoading: Bool = false
    @Published var isWrongPassword: Bool = false

    private var initialPassword: String = .empty

    private let keychain = DefaultKeychainService.shared
    private let fastVaultService = FastVaultService.shared

    func setData(vault: Vault) {
        if let password = keychain.getFastPassword(pubKeyECDSA: vault.pubKeyECDSA) {
            self.password = password
            self.initialPassword = password
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
        return password != initialPassword && !password.isEmpty
    }

    @MainActor func validatePassword(vault: Vault) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        let isValid = await fastVaultService.get(
            pubKeyECDSA:  vault.pubKeyECDSA,
            password: password
        )

        guard isValid else {
            isWrongPassword = true
            return false
        }

        keychain.setFastPassword(
            password.isEmpty ? nil : password,
            pubKeyECDSA: vault.pubKeyECDSA
        )

        return true
    }
}
