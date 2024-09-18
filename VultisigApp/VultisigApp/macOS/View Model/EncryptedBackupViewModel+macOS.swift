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
}
#endif
