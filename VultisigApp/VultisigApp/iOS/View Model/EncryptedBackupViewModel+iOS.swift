//
//  EncryptedBackupViewModel+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI
import UIKit

extension EncryptedBackupViewModel {
    func promptForPasswordAndImport(from data: Data) {
        let alert = UIAlertController(title: NSLocalizedString("enterPassword", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = NSLocalizedString("password", comment: "").capitalized
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let password = alert.textFields?.first?.text {
                self.decryptionPassword = password
                self.importFileWithPassword(from: data, password: password)
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }
}
#endif
