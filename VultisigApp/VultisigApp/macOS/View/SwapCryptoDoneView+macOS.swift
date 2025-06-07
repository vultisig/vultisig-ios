//
//  SwapCryptoDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-08.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoDoneView {
    func copyValue(_ value: String) {
        alertTitle = "hashCopied"
        showAlert = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            trackButton
            doneButton
        }
        .padding(.vertical)
        .padding(.horizontal, 18)
        .background(Color.backgroundBlue)
    }
}
#endif
