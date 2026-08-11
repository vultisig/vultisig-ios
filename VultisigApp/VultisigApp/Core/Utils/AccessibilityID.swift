//
//  AccessibilityID.swift
//  VultisigApp
//

import Foundation

enum AccessibilityID {
    enum Home {
        static let walletTab = "home.walletTab"
        static let defiTab = "home.defiTab"
        static let agentTab = "home.agentTab"
        static let settingsButton = "home.settingsButton"
        static let historyButton = "home.historyButton"
        static let vaultSelector = "home.vaultSelector"
        static let cameraButton = "home.cameraButton"
        static let balanceLabel = "home.balanceLabel"
    }

    enum Settings {
        static let container = "settings.container"
        static let languageCell = "settings.languageCell"
        static let currencyCell = "settings.currencyCell"
        static let vaultSettingsCell = "settings.vaultSettingsCell"
        static let faqCell = "settings.faqCell"
        static let managePasscodeCell = "settings.managePasscodeCell"
        static let autoLockCell = "settings.autoLockCell"
        static let biometricUnlockToggle = "settings.biometricUnlockToggle"
        static let biometricUnlockNote = "settings.biometricUnlockNote"
    }

    enum Passcode {
        static let dots = "passcode.dots"
        static let deleteKey = "passcode.deleteKey"
        static let enterScreen = "passcode.enterScreen"
        static let awaitingBiometrics = "passcode.awaitingBiometrics"
        static let keyshareRecoveryScreen = "passcode.keyshareRecoveryScreen"
        static let keyshareRecoveryImportButton = "passcode.keyshareRecoveryImportButton"
        static let keyshareRecoveryNoBackupToggle = "passcode.keyshareRecoveryNoBackupToggle"

        static func digitKey(_ digit: String) -> String {
            "passcode.digit.\(digit)"
        }
    }

    enum Onboarding {
        static let createVaultButton = "onboarding.createVaultButton"
        static let importVaultButton = "onboarding.importVaultButton"
        static let vaultNameField = "onboarding.vaultNameField"
    }

    enum Splash {
        static let tryAgainButton = "splash.tryAgainButton"
    }
}
