//
//  MemoTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension MemoTextField {
    var container: some View {
        content
    }

    func pasteAddress() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            memo = clipboardContent
        }
    }
}
#endif
