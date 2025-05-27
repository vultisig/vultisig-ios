//
//  SwapCryptoDoneView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-08.
//

#if os(iOS)
import SwiftUI

extension SwapCryptoDoneView {
    func copyValue(_ value: String) {
        alertTitle = "hashCopied"
        showAlert = true
        let pasteboard = UIPasteboard.general
        pasteboard.string = value
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            trackButton
            doneButton
        }
        .padding(.top)
        .padding(.horizontal, 18)
        .background(Color.backgroundBlue)
    }
}
#endif
