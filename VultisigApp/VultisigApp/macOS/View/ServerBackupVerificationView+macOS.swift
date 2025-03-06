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
        }
        .padding(.horizontal, 40)
    }

    var textField: some View {
        HStack(spacing: 8) {
            field
                .multilineTextAlignment(.center)
            pasteButton
        }
        .colorScheme(.dark)
        .padding(.top, 32)
    }

    func pasteCode() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string), clipboardContent.count == Self.codeLength {
            otp = clipboardContent
                .map { String($0) }
        }
    }
}
#endif
