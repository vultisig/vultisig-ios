//
//  ReferralTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(macOS)
import SwiftUI

extension ReferralTextField {
    func handleCopyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func handlePasteCode() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            text = clipboardContent
        }
    }
}
#endif
