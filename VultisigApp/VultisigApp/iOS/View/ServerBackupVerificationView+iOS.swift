//
//  ServerBackupVerificationView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

#if os(iOS)
import SwiftUI

extension ServerBackupVerificationView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
        .padding(.horizontal, 16)
    }


    var textField: some View {
        HStack(spacing: 8) {
            field
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
            pasteButton
        }
        .colorScheme(.dark)
        .padding(.top, 32)
    }

    func pasteCode() {
        if let clipboardContent = UIPasteboard.general.string, clipboardContent.count == Self.codeLength {
            otp = clipboardContent.map { String($0) }
        }
    }
}
#endif
