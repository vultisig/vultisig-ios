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
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
    }

    func handlePasteCode() {
        if let clipboardContent = UIPasteboard.general.string {
            text = clipboardContent
        }
    }
}
#endif
