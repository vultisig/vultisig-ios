//
//  ReferralTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(iOS)
import SwiftUI

extension ReferralTextField {
    func handleCopyCode() {
        
    }
    
    func handlePasteCode() {
        if let clipboardContent = UIPasteboard.general.string {
            text = clipboardContent
        }
    }
}
#endif
