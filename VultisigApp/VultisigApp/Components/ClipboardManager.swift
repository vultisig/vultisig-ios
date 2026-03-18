//
//  ClipboardManager.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/07/2025.
//

import SwiftUI

enum ClipboardManager {
    static func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }

    static func pasteFromClipboard() -> String? {
#if os(iOS)
        return UIPasteboard.general.string
#elseif os(macOS)
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
#endif
    }
}
