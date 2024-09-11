//
//  ChainHeaderCell+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension ChainHeaderCell {
    var showQRButton: some View {
        Button(action: {
            isLoading = true
            showQRcode.toggle()
        }, label: {
            qrCodeLabel
        })
    }
    
    func copyAddress() {
        showAlert = true
        
        let pasteboard = UIPasteboard.general
        pasteboard.string = group.address
    }
}
#endif
