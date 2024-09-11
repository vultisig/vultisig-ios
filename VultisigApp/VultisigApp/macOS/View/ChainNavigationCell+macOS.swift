//
//  ChainNavigationCell+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-10.
//

#if os(macOS)
import SwiftUI

extension ChainNavigationCell {
    func copyAddress() {
        showAlert = true
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(group.address, forType: .string)
    }
}
#endif
