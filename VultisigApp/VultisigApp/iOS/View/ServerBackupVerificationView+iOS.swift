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
    
    func pasteCode() {
        if let clipboardContent = UIPasteboard.general.string {
            otp = clipboardContent.map { String($0) }
        }
    }
}
#endif
