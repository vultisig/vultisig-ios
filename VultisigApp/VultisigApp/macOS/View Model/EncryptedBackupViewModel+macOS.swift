//
//  EncryptedBackupViewModel+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI
import AppKit

extension EncryptedBackupViewModel {
    func promptForPasswordAndImport(from data: Data) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("enterPassword", comment: "")
        alert.informativeText = ""
        alert.alertStyle = .informational

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("password", comment: "").capitalized
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard let mainWindow = NSApplication.shared.mainWindow else {
            let alertWindow = alert.window
            let screenFrame = NSScreen.main?.frame ?? NSRect.zero
            let alertFrame = alertWindow.frame
            let centerX = screenFrame.midX - alertFrame.width / 2
            let centerY = screenFrame.midY - alertFrame.height / 2
            alertWindow.setFrameOrigin(NSPoint(x: centerX, y: centerY))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                self.decryptionPassword = password
                self.importFileWithPassword(from: data, password: password)
            }
            return
        }

        // Show the alert as a sheet attached to the main window
        alert.beginSheetModal(for: mainWindow) { response in
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                self.decryptionPassword = password
                self.importFileWithPassword(from: data, password: password)
            }
        }
    }

    func promptForPasswordAndImportMultiple(encryptedVaultData: [(fileName: String, data: Data)], processedVaults: [Vault]) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("enterPassword", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Found %d encrypted vault(s). Enter password to decrypt:", comment: ""), encryptedVaultData.count)
        alert.alertStyle = .informational

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("password", comment: "").capitalized
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                let password = textField.stringValue
                self.decryptionPassword = password
                self.processEncryptedVaults(encryptedVaultData: encryptedVaultData, processedVaults: processedVaults, password: password)
            } else if response == .alertSecondButtonReturn {
                // Clear pending encrypted vaults on cancel
                self.pendingEncryptedVaults = []

                // If user cancels, still import the non-encrypted vaults
                if !processedVaults.isEmpty {
                    self.multipleVaultsToImport = processedVaults
                    self.isMultipleVaultImport = true
                    self.isFileUploaded = true
                } else {
                    self.showError(NSLocalizedString("noUnencryptedVaultsToImport", comment: "Shown when there are no unencrypted vaults available to import"))
                }
            }
        }

        guard let mainWindow = NSApplication.shared.mainWindow else {
            let alertWindow = alert.window
            let screenFrame = NSScreen.main?.frame ?? NSRect.zero
            let alertFrame = alertWindow.frame
            let centerX = screenFrame.midX - alertFrame.width / 2
            let centerY = screenFrame.midY - alertFrame.height / 2
            alertWindow.setFrameOrigin(NSPoint(x: centerX, y: centerY))

            let response = alert.runModal()
            handleResponse(response)
            return
        }

        // Show the alert as a sheet attached to the main window
        alert.beginSheetModal(for: mainWindow) { response in
            handleResponse(response)
        }
    }
}
#endif
