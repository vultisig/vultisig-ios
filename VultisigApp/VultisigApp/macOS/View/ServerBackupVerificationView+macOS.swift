//
//  ServerBackupVerificationView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(macOS)
import SwiftUI

extension ServerBackupVerificationView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var header: some View {
        ServerBackupVerificationHeader()
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            description
            textField
            
            if isLoading {
                loadingText
            }
            
            if showAlert {
                alertText
            }
            
            Spacer()
            buttons
        }
        .padding(.horizontal, 40)
    }
    
    func pasteCode() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            verificationCode = clipboardContent
        }
    }
}
#endif
